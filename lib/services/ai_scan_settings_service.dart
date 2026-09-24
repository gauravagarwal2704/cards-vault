import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AiScanProvider {
  gemini,
  openAi;

  String get label => switch (this) {
    AiScanProvider.gemini => 'Google Gemini',
    AiScanProvider.openAi => 'OpenAI',
  };

  String get modelLabel => switch (this) {
    AiScanProvider.gemini => 'Gemini 3.5 Flash-Lite',
    AiScanProvider.openAi => 'GPT-5.6 Luna',
  };

  String get apiModelId => switch (this) {
    AiScanProvider.gemini => 'gemini-3.5-flash-lite',
    AiScanProvider.openAi => 'gpt-5.6-luna',
  };

  String get processingDisclosure =>
      'CardVault sends up to three cropped, resized card images directly to '
      '$label for processing by $modelLabel. The images can contain the card '
      'number, expiry date, and cardholder name. CardVault removes image '
      'metadata and does not send offline OCR text, CVV, other saved cards, or '
      'unrelated app data.';

  String get retentionDisclosure =>
      'CardVault does not keep a remote copy or control $label\'s processing '
      'or retention. $label may log or retain request data according to your '
      'provider account settings and its current terms.';
}

class AiScanSettings {
  final bool enabled;
  final AiScanProvider provider;
  final String apiKey;
  final bool hasProcessingConsent;

  const AiScanSettings({
    this.enabled = false,
    this.provider = AiScanProvider.gemini,
    this.apiKey = '',
    this.hasProcessingConsent = false,
  });

  bool get hasApiKey => apiKey.trim().isNotEmpty;
  bool get isConfigured => enabled && hasApiKey && hasProcessingConsent;
}

/// Stores only non-secret preferences in SharedPreferences. Provider keys are
/// isolated in platform secure storage and are not synchronized to other
/// devices. The settings UI loads key presence, not the saved key value.
class AiScanSettingsService {
  static const processingConsentVersion = 1;
  static const _enabledKey = 'ai_scan_enabled';
  static const _providerKey = 'ai_scan_provider';
  static const _riskAcceptedKey = 'ai_scan_byok_risk_accepted';
  static const _consentMigrationKey =
      'ai_scan_processing_consent_v1_migration_complete';
  static const _migrationKey = 'ai_scan_byok_migration_complete';
  static const _legacyEndpointKey = 'ai_scan_endpoint';
  static const _legacyProxyTokenKey = 'ai_scan_proxy_token';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true,
      sharedPreferencesName: 'cardvault_ai_credentials',
      preferencesKeyPrefix: 'cardvault_ai_',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      accountName: 'CardVault Smart Scan',
    ),
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      synchronizable: false,
      accountName: 'CardVault Smart Scan',
      useDataProtectionKeyChain: true,
    ),
  );

  final FlutterSecureStorage _legacySecureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<AiScanSettings> load({bool includeApiKey = true}) async {
    await _removeLegacyProxyCredentials();
    final preferences = await SharedPreferences.getInstance();
    await _migrateToExplicitConsent(preferences);
    final provider = _providerFromName(preferences.getString(_providerKey));
    final hasProcessingConsent = _hasCurrentConsent(preferences, provider);
    var enabled = preferences.getBool(_enabledKey) ?? false;
    if (enabled && !hasProcessingConsent) {
      enabled = false;
      await preferences.setBool(_enabledKey, false);
    }
    return AiScanSettings(
      enabled: enabled,
      provider: provider,
      apiKey: includeApiKey
          ? await _secureStorage.read(key: _storageKey(provider)) ?? ''
          : '',
      hasProcessingConsent: hasProcessingConsent,
    );
  }

  Future<void> savePreferences({
    required bool enabled,
    required AiScanProvider provider,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateToExplicitConsent(preferences);
    if (enabled && !_hasCurrentConsent(preferences, provider)) {
      throw StateError(
        'Explicit ${provider.label} processing consent is required before '
        'SmartAI can be enabled.',
      );
    }
    await preferences.setBool(_enabledKey, enabled);
    await preferences.setString(_providerKey, provider.name);
  }

  Future<bool> hasProcessingConsent(AiScanProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateToExplicitConsent(preferences);
    return _hasCurrentConsent(preferences, provider);
  }

  Future<void> acceptProcessingConsent(AiScanProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    await _migrateToExplicitConsent(preferences);
    await preferences.setInt(
      _processingConsentKey(provider),
      processingConsentVersion,
    );
  }

  Future<void> revokeProcessingConsent(AiScanProvider provider) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_processingConsentKey(provider));
    if (preferences.getString(_providerKey) == provider.name) {
      await preferences.setBool(_enabledKey, false);
    }
  }

  Future<bool> hasApiKey(AiScanProvider provider) async {
    final value = await _secureStorage.read(key: _storageKey(provider));
    return value != null && value.trim().isNotEmpty;
  }

  Future<void> saveApiKey(AiScanProvider provider, String apiKey) async {
    final sanitized = apiKey.trim();
    if (sanitized.isEmpty) {
      throw ArgumentError.value(apiKey, 'apiKey', 'API key cannot be empty');
    }
    await _secureStorage.write(key: _storageKey(provider), value: sanitized);
  }

  Future<void> deleteApiKey(AiScanProvider provider) {
    return _secureStorage.delete(key: _storageKey(provider));
  }

  String _storageKey(AiScanProvider provider) {
    return 'ai_scan_api_key_${provider.name}_v1';
  }

  String _processingConsentKey(AiScanProvider provider) {
    return 'ai_scan_processing_consent_${provider.name}_v1';
  }

  bool _hasCurrentConsent(
    SharedPreferences preferences,
    AiScanProvider provider,
  ) {
    return preferences.getInt(_processingConsentKey(provider)) ==
        processingConsentVersion;
  }

  AiScanProvider _providerFromName(String? name) {
    return AiScanProvider.values.firstWhere(
      (provider) => provider.name == name,
      orElse: () => AiScanProvider.gemini,
    );
  }

  Future<void> _removeLegacyProxyCredentials() async {
    final preferences = await SharedPreferences.getInstance();
    if (preferences.getBool(_migrationKey) == true) return;

    // The previous experimental proxy token must never be reinterpreted as a
    // provider key. Remove it once when moving to the explicit BYOK design.
    await _legacySecureStorage.delete(key: _legacyProxyTokenKey);
    await preferences.remove(_legacyEndpointKey);
    await preferences.setBool(_enabledKey, false);
    await preferences.setBool(_migrationKey, true);
  }

  Future<void> _migrateToExplicitConsent(SharedPreferences preferences) async {
    if (preferences.getBool(_consentMigrationKey) == true) return;

    // The former acknowledgement did not identify a provider, explain its
    // retention, or constitute informed processing consent. Never promote it
    // to the new consent record; require a fresh opt-in instead.
    await preferences.remove(_riskAcceptedKey);
    await preferences.setBool(_enabledKey, false);
    await preferences.setBool(_consentMigrationKey, true);
  }
}
