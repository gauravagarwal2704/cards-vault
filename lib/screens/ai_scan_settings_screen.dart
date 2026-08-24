import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/ai_card_scan_service.dart';
import '../services/ai_scan_log_service.dart';
import '../services/ai_scan_settings_service.dart';
import '../services/auth_service.dart';
import '../theme/app_typography.dart';
import '../theme/app_colors.dart';
import 'ai_scan_logs_screen.dart';

class AiScanSettingsScreen extends StatefulWidget {
  const AiScanSettingsScreen({super.key});

  @override
  State<AiScanSettingsScreen> createState() => _AiScanSettingsScreenState();
}

class _AiScanSettingsScreenState extends State<AiScanSettingsScreen> {
  final _settingsService = AiScanSettingsService();
  final _scanService = AiCardScanService();
  final _logService = AiScanLogService();
  final _authService = AuthService();

  AiScanProvider _provider = AiScanProvider.gemini;
  AiScanProvider? _testingProvider;
  bool _enabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _loggingEnabled = true;
  int _logCount = 0;
  Map<AiScanProvider, bool> _savedKeyByProvider = {
    for (final provider in AiScanProvider.values) provider: false,
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final settings = await _settingsService.load(includeApiKey: false);
    final loggingEnabled = await _logService.isLoggingEnabled();
    final logs = await _logService.load();
    final entries = await Future.wait(
      AiScanProvider.values.map(
        (provider) async =>
            MapEntry(provider, await _settingsService.hasApiKey(provider)),
      ),
    );
    final savedKeys = Map<AiScanProvider, bool>.fromEntries(entries);
    if (!mounted) return;
    setState(() {
      _provider = settings.provider;
      _enabled = settings.enabled && (savedKeys[settings.provider] ?? false);
      _savedKeyByProvider = savedKeys;
      _loggingEnabled = loggingEnabled;
      _logCount = logs.length;
      _loading = false;
    });
  }

  Future<void> _setEnabled(bool value) async {
    if (value && !(_savedKeyByProvider[_provider] ?? false)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Add and verify a ${_provider.label} API key first.'),
        ),
      );
      return;
    }
    if (value && !await _settingsService.hasAcceptedByokRisk()) {
      if (!mounted) return;
      final accepted = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded),
          title: const Text('Enable advanced BYOK mode?'),
          content: Text(
            'Your card image will be sent directly to ${_provider.label} using your key. The provider may process sensitive card data and charge your account. Secure storage reduces risk, but no mobile app can make a long-lived API key impossible to extract from a compromised device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('I understand'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
      await _settingsService.acceptByokRisk();
      if (!mounted) return;
    }
    setState(() => _enabled = value);
  }

  void _selectProvider(AiScanProvider provider) {
    if (_testingProvider != null || provider == _provider) return;
    final hasKey = _savedKeyByProvider[provider] ?? false;
    setState(() {
      _provider = provider;
      if (!hasKey) _enabled = false;
    });
    if (!hasKey) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Add a ${provider.label} key before enabling SmartAI scan.',
          ),
        ),
      );
    }
  }

  Future<String?> _promptForKey(AiScanProvider provider, bool replacing) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    var obscure = true;
    final value = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          icon: const Icon(Icons.key_outlined),
          title: Text(
            replacing
                ? 'Update ${provider.label} key'
                : 'Add ${provider.label} key',
          ),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              obscureText: obscure,
              autocorrect: false,
              enableSuggestions: false,
              keyboardType: TextInputType.visiblePassword,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Enter your ${provider.label} API key.';
                }
                if (value.trim().length < 16) {
                  return 'This API key appears too short.';
                }
                return null;
              },
              decoration: InputDecoration(
                labelText: '${provider.label} API key',
                helperText: replacing
                    ? 'The existing key stays protected until this replacement is verified.'
                    : 'The key is verified before secure storage.',
                suffixIcon: IconButton(
                  onPressed: () => setDialogState(() => obscure = !obscure),
                  icon: Icon(obscure ? Icons.visibility : Icons.visibility_off),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton.icon(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              icon: const Icon(Icons.verified_outlined),
              label: const Text('Verify key'),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    return value;
  }

  Future<void> _addOrUpdateKey(AiScanProvider provider) async {
    final replacing = _savedKeyByProvider[provider] ?? false;
    final apiKey = await _promptForKey(provider, replacing);
    if (apiKey == null || !mounted) return;

    if (replacing) {
      final authenticated = await _authService.authenticateForCardDetails(
        reason: 'Authenticate to replace the saved ${provider.label} key',
      );
      if (!authenticated || !mounted) return;
    }

    setState(() => _testingProvider = provider);
    final result = await _scanService.validateApiKey(
      provider: provider,
      apiKey: apiKey,
    );
    if (!mounted) return;
    if (!result.isValid) {
      setState(() => _testingProvider = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
      return;
    }

    try {
      await _settingsService.saveApiKey(provider, apiKey);
      if (!mounted) return;
      setState(() {
        _savedKeyByProvider[provider] = true;
        _testingProvider = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppSemanticColors.of(context).success,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _testingProvider = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('The API key could not be saved securely.'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _deleteSavedKey(AiScanProvider provider) async {
    final authenticated = await _authService.authenticateForCardDetails(
      reason: 'Authenticate to remove the saved ${provider.label} key',
    );
    if (!authenticated || !mounted) return;

    final selected = provider == _provider;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Remove ${provider.label} key?'),
        content: Text(
          selected
              ? 'SmartAI scanning will be disabled. Offline card scanning will continue to work.'
              : 'The saved key will be permanently removed from this device.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Remove key'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _settingsService.deleteApiKey(provider);
    if (selected) {
      await _settingsService.savePreferences(
        enabled: false,
        provider: provider,
      );
    }
    if (!mounted) return;
    setState(() {
      _savedKeyByProvider[provider] = false;
      if (selected) _enabled = false;
    });
  }

  Future<void> _savePreferences() async {
    if (_enabled && !(_savedKeyByProvider[_provider] ?? false)) {
      await _setEnabled(true);
      return;
    }
    setState(() => _saving = true);
    await _settingsService.savePreferences(
      enabled: _enabled,
      provider: _provider,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _enabled
              ? 'SmartAI scanning enabled with ${_provider.label}.'
              : 'SmartAI scanning is off. Scans stay on device.',
        ),
      ),
    );
  }

  Future<void> _setLoggingEnabled(bool value) async {
    await _logService.setLoggingEnabled(value);
    if (!mounted) return;
    setState(() => _loggingEnabled = value);
  }

  Future<void> _openLogs() async {
    final authenticated = await _authService.authenticateForCardDetails(
      reason: 'Authenticate to view sensitive SmartAI scan logs',
    );
    if (!authenticated || !mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const AiScanLogsScreen()),
    );
    final logs = await _logService.load();
    if (!mounted) return;
    setState(() => _logCount = logs.length);
  }

  Widget _providerKeySection(
    ThemeProvider theme,
    AiScanProvider provider,
    Color primary,
    Color secondary,
  ) {
    final selected = provider == _provider;
    final hasKey = _savedKeyByProvider[provider] ?? false;
    final testing = _testingProvider == provider;

    return Container(
      decoration: BoxDecoration(
        color: theme.getCardColor(),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: selected ? theme.seedColor : theme.getOutlineColor(),
          width: selected ? 1.5 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        leading: IconButton(
          tooltip: 'Use ${provider.label}',
          onPressed: () => _selectProvider(provider),
          icon: Icon(
            selected ? Icons.radio_button_checked : Icons.radio_button_off,
            color: selected ? theme.seedColor : secondary,
          ),
        ),
        title: Text(
          '${provider.label} key',
          style: AppTypography.listItem(color: primary)
              .copyWith(fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          hasKey ? 'Key saved securely' : 'No key saved',
          style: AppTypography.caption(color: secondary),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 14),
          Row(
            children: [
              Icon(Icons.memory_outlined, size: 20, color: secondary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.modelLabel,
                      style: AppTypography.body(color: primary)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    Text(
                      'CardVault-managed compatible extraction model',
                      style: AppTypography.caption(color: secondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _testingProvider == null
                    ? () => _addOrUpdateKey(provider)
                    : null,
                icon: testing
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(hasKey ? Icons.edit_outlined : Icons.add),
                label: Text(
                  testing
                      ? 'Verifying…'
                      : hasKey
                      ? 'Update key'
                      : 'Add key',
                ),
              ),
              if (hasKey)
                OutlinedButton.icon(
                  onPressed: _testingProvider == null
                      ? () => _deleteSavedKey(provider)
                      : null,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete key'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _diagnosticsSection(
    ThemeProvider theme,
    Color primary,
    Color secondary,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: theme.getCardColor(),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.getOutlineColor()),
      ),
      child: Column(
        children: [
          SwitchListTile(
            value: _loggingEnabled,
            onChanged: _setLoggingEnabled,
            secondary: Icon(
              Icons.history_outlined,
              color: theme.getPrimaryColor(),
            ),
            title: Text(
              'Encrypted diagnostic logs',
              style: AppTypography.listItem(color: primary)
                  .copyWith(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              'Keep the 10 newest sanitized requests and provider responses.',
              style: AppTypography.caption(color: secondary),
            ),
          ),
          const Divider(height: 1),
          ListTile(
            onTap: _openLogs,
            leading: Icon(Icons.receipt_long_outlined, color: secondary),
            title: Text(
              'View scan logs',
              style: AppTypography.listItem(color: primary)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _logCount == 0
                  ? 'No logs yet'
                  : '$_logCount recent log${_logCount == 1 ? '' : 's'}',
              style: AppTypography.caption(color: secondary),
            ),
            trailing: Icon(Icons.chevron_right, color: secondary),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final primary = theme.getPrimaryTextColor();
    final secondary = theme.getSecondaryTextColor();

    return Scaffold(
      backgroundColor: theme.getBackgroundColor(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Smart AI scan',
          style: AppTypography.appBarTitle(color: primary),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            IconButton(
              key: const ValueKey('save-smart-ai-settings'),
              tooltip: 'Save SmartAI settings',
              onPressed: _loading ? null : _savePreferences,
              icon: const Icon(Icons.check),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: theme.getCardColor(),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: theme.getOutlineColor()),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.auto_awesome, color: theme.seedColor),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Bring your own key',
                              style: AppTypography.listItem(color: primary)
                                  .copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Switch(value: _enabled, onChanged: _setEnabled),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Offline recognition runs first. If it is incomplete, CardVault asks before sending up to three metadata-free card frames to the selected provider.',
                        style: AppTypography.body(color: secondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Provider keys',
                  style: AppTypography.sectionTitle(color: primary),
                ),
                const SizedBox(height: 8),
                Text(
                  'Choose the active provider with the circle. Expand either key to add, update, or delete it directly.',
                  style: AppTypography.body(color: secondary),
                ),
                const SizedBox(height: 12),
                for (final provider in AiScanProvider.values) ...[
                  _providerKeySection(theme, provider, primary, secondary),
                  const SizedBox(height: 12),
                ],
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.shield_outlined, size: 18, color: secondary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Keys are kept in protected device storage and never displayed again. Use dedicated restricted keys with billing limits. CardVault never requests CVV.',
                        style: AppTypography.caption(color: secondary),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 26),
                Text(
                  'Scan diagnostics',
                  style: AppTypography.sectionTitle(color: primary),
                ),
                const SizedBox(height: 10),
                _diagnosticsSection(theme, primary, secondary),
              ],
            ),
    );
  }
}
