import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers/theme_provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/profile_provider.dart';
import '../providers/app_icon_provider.dart';
import '../services/secure_card_storage.dart';
import '../services/auth_service.dart';
import '../services/app_log_service.dart';
import '../models/theme_config.dart' as config;

import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_typography.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../widgets/backup_password_dialog.dart';
import '../widgets/app_icon_artwork.dart';
import '../utils/debug_logger.dart';
import 'appearance_screen.dart';
import 'developer_options_screen.dart';
import 'privacy_policy_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.onCardsChanged});

  final Future<void> Function()? onCardsChanged;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const String _developerOptionsEnabledKey = 'developer_options_enabled';
  static final Uri _repositoryUrl = Uri.parse(
    'https://github.com/gauravagarwal2704/cards-vault',
  );
  static final Uri _telegramUrl = Uri.parse('https://t.me/CardVaultApp');
  static final Uri _buyMeACoffeeUrl = Uri.parse(
    'https://buymeacoffee.com/gauravagarwal',
  );
  static final Uri _buyMeAChaiUrl = Uri.parse(
    'https://buymeachai.in/gauravagarwal',
  );

  final SecureCardStorage _cardStorage = SecureCardStorage();
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isDeletingAll = false;
  String? _lastBackupDate;
  int _cardCount = 0;
  String _appVersion = '';
  List<BiometricType> _availableBiometrics = [];
  int _versionTapCount = 0;
  bool _developerOptionsUnlocked = false;

  @override
  void initState() {
    super.initState();
    AppLogService.instance.action('Navigation', 'Opened Settings');
    _loadDeveloperOptionsPreference();
    _loadData();
  }

  Future<void> _loadDeveloperOptionsPreference() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final enabled = preferences.getBool(_developerOptionsEnabledKey) ?? false;
      DebugLogger.setEnabled(enabled);
      if (!mounted) return;
      setState(() => _developerOptionsUnlocked = enabled);
    } catch (error) {
      AppLogService.instance.record(
        'Settings',
        'Developer options preference load failed: ${error.runtimeType}',
      );
    }
  }

  Future<void> _loadData() async {
    final authentication =
        context.read<AuthenticationCoordinator?>() ??
        AuthenticationCoordinator();
    final lastBackup = await _cardStorage.getLastBackupDate();
    final count = await _cardStorage.getCardCount();
    final biometrics = await authentication.getAvailableBiometrics();
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _lastBackupDate = lastBackup;
        _cardCount = count;
        _appVersion = packageInfo.version;
        _availableBiometrics = biometrics;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _lastBackupDate = lastBackup;
        _cardCount = count;
        _availableBiometrics = biometrics;
      });
    }
  }

  IconData _getBiometricIcon() {
    if (_availableBiometrics.contains(BiometricType.face)) {
      return Icons.face;
    } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return Icons.fingerprint;
    }
    return Icons.lock;
  }

  String _getBiometricName() {
    if (_availableBiometrics.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    }
    return 'Biometric';
  }

  Future<void> _editDisplayName() async {
    final profile = context.read<ProfileProvider>();

    final name = await showDialog<String>(
      context: context,
      builder: (_) => _EditDisplayNameDialog(initialName: profile.displayName),
    );

    if (name != null && mounted) {
      await profile.setDisplayName(name);
      AppLogService.instance.action('Settings', 'Display name updated');
    }
  }

  Future<void> _deleteAllCards() async {
    if (_cardCount == 0 || _isDeletingAll) return;

    final count = _cardCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete all cards?'),
        content: Text(
          'All $count saved card${count == 1 ? '' : 's'} and their photos will '
          'be permanently deleted. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('confirm-delete-all-cards'),
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;
    setState(() => _isDeletingAll = true);

    try {
      await _cardStorage.deleteAllCards();
      AppLogService.instance.action(
        'Cards',
        'Deleted all cards',
        details: {'count': count},
      );
      await widget.onCardsChanged?.call();
      if (!mounted) return;
      setState(() {
        _cardCount = 0;
        _isDeletingAll = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('All cards deleted'),
          backgroundColor: AppSemanticColors.of(context).success,
        ),
      );
    } catch (e) {
      AppLogService.instance.record('Cards', 'Delete all cards failed: $e');
      if (!mounted) return;
      setState(() => _isDeletingAll = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to delete all cards: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<String?> _promptBackupPassword({
    required String title,
    required String confirmLabel,
    bool requireConfirm = false,
  }) {
    return promptBackupPassword(
      context,
      title: title,
      confirmLabel: confirmLabel,
      requireConfirm: requireConfirm,
    );
  }

  /// Returns how the backup should be applied, or null if the user backed out.
  Future<BackupImportMode?> _promptImportMode() async {
    if (_cardCount == 0) return BackupImportMode.merge;

    final themeProvider = context.read<ThemeProvider>();

    return showDialog<BackupImportMode>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.getCardColor(),
        title: Text(
          'Import Backup',
          style: AppTypography.dialogTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
        content: Text(
          'You already have $_cardCount card${_cardCount != 1 ? 's' : ''} saved. '
          'Add the cards from this backup to your list, or replace everything '
          'with the contents of the backup?',
          style: AppTypography.body(
            color: themeProvider.getSecondaryTextColor(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, BackupImportMode.replace),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Replace all'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, BackupImportMode.merge),
            child: const Text('Add to list'),
          ),
        ],
      ),
    );
  }

  Future<bool> _confirmReplace() async {
    final themeProvider = context.read<ThemeProvider>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.getCardColor(),
        title: Text(
          'Replace all cards?',
          style: AppTypography.dialogTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
        content: Text(
          'Your $_cardCount saved card${_cardCount != 1 ? 's' : ''}, their photos '
          'and groups will be deleted and replaced by the backup. This cannot be undone.',
          style: AppTypography.body(
            color: themeProvider.getSecondaryTextColor(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Replace'),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  /// Returns whether photos should be bundled, or null if the user backed out.
  Future<bool?> _promptIncludePhotos(int photosBytes) async {
    if (photosBytes == 0) return false;

    final themeProvider = context.read<ThemeProvider>();
    final sizeLabel = _formatBytes(photosBytes);

    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.getCardColor(),
        title: Text(
          'Include Photos?',
          style: AppTypography.dialogTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
        content: Text(
          'Bundling your card photos adds about $sizeLabel to the backup, but means '
          'a file shared offline restores everything. Without photos the backup '
          'stays small and carries card details only.',
          style: AppTypography.body(
            color: themeProvider.getSecondaryTextColor(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Details only'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('Include ($sizeLabel)'),
          ),
        ],
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _exportBackup() async {
    final authentication =
        context.read<AuthenticationCoordinator?>() ??
        AuthenticationCoordinator();
    final authenticated = await authentication.authorize(
      ProtectedAction.exportVault,
    );
    if (!authenticated || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authentication.lastErrorMessage ?? 'Authentication required',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }

    final photosBytes = await _cardStorage.getPhotosSizeInBytes();
    if (!mounted) return;

    final includePhotos = await _promptIncludePhotos(photosBytes);
    if (includePhotos == null || !mounted) return;

    final password = await _promptBackupPassword(
      title: 'Export Backup',
      confirmLabel: 'Export',
      requireConfirm: true,
    );
    if (password == null) return;

    setState(() => _isExporting = true);
    await WidgetsBinding.instance.endOfFrame;

    try {
      final filePath = await _cardStorage.exportBackup(
        password,
        includePhotos: includePhotos,
      );
      AppLogService.instance.action(
        'Backup',
        'Backup exported',
        details: {'includePhotos': includePhotos},
      );

      if (mounted) {
        await _loadData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved to:\n$filePath'),
            backgroundColor: AppSemanticColors.of(context).success,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Share',
              textColor: Theme.of(context).colorScheme.onInverseSurface,
              onPressed: () => Share.shareXFiles([
                XFile(filePath),
              ], subject: 'CardVault backup'),
            ),
          ),
        );
      }
    } catch (e) {
      AppLogService.instance.record('Backup', 'Backup export failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cwbak', 'json'],
    );

    if (result == null || result.files.single.path == null) return;

    final filePath = result.files.single.path!;
    if (!mounted) return;

    final mode = await _promptImportMode();
    if (mode == null || !mounted) return;

    if (mode == BackupImportMode.replace) {
      final confirmed = await _confirmReplace();
      if (!confirmed || !mounted) return;
    }

    String? password;

    try {
      final content = await File(filePath).readAsString();
      final backupData = jsonDecode(content) as Map<String, dynamic>;
      final version = backupData['version'];
      if (version == '2.0' || version == '3.0') {
        password = await _promptBackupPassword(
          title: 'Import Backup',
          confirmLabel: 'Import',
        );
        if (password == null) return;
      } else {
        password = '';
      }
    } catch (_) {
      password = await _promptBackupPassword(
        title: 'Import Backup',
        confirmLabel: 'Import',
      );
      if (password == null) return;
    }

    setState(() => _isImporting = true);
    await WidgetsBinding.instance.endOfFrame;

    try {
      final importedCount = await _cardStorage.importBackup(
        filePath,
        password,
        mode: mode,
      );
      AppLogService.instance.action(
        'Backup',
        'Backup imported',
        details: {'mode': mode.name, 'count': importedCount},
      );

      if (mounted) {
        await widget.onCardsChanged?.call();
        if (!mounted) return;
        await _loadData();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mode == BackupImportMode.replace
                  ? 'Replaced your cards with $importedCount from the backup'
                  : 'Successfully imported $importedCount cards',
            ),
            backgroundColor: AppSemanticColors.of(context).success,
          ),
        );
      }
    } catch (e) {
      AppLogService.instance.record('Backup', 'Backup import failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _handleVersionTap() async {
    if (_developerOptionsUnlocked) return;
    final taps = _versionTapCount + 1;
    if (taps >= 5) {
      setState(() {
        _versionTapCount = 5;
        _developerOptionsUnlocked = true;
      });
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_developerOptionsEnabledKey, true);
      DebugLogger.setEnabled(true);
      AppLogService.instance.action('Settings', 'Developer options enabled');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(content: Text('Developer options unlocked')),
        );
      return;
    }
    setState(() => _versionTapCount = taps);
    if (taps >= 2) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('${5 - taps} more taps to unlock developer options'),
          ),
        );
    }
  }

  Future<void> _setAppLockEnabled(
    AppLockProvider appLockProvider,
    bool enabled,
  ) async {
    final authentication =
        context.read<AuthenticationCoordinator?>() ??
        AuthenticationCoordinator();
    final authenticated = await authentication.authorize(
      ProtectedAction.changeSecuritySettings,
      reason: enabled
          ? 'Authenticate to enable app lock'
          : 'Authenticate to disable app lock',
    );
    if (!authenticated || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              authentication.lastErrorMessage ?? 'Authentication required',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
      return;
    }
    await appLockProvider.setAppLockEnabled(enabled);
  }

  Future<void> _openExternalLink(Uri url, String destination) async {
    AppLogService.instance.action(
      'Settings',
      'External link requested',
      details: {'destination': destination},
    );
    try {
      final opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Could not open $destination')));
  }

  void _showOpenSourceLicenses() {
    showLicensePage(
      context: context,
      applicationName: 'CardVault',
      applicationVersion: _appVersion.isEmpty ? '1.2.1' : _appVersion,
      applicationLegalese: 'Open-source software licenses',
    );
  }

  void _showPrivacyPolicy() {
    AppLogService.instance.action('Navigation', 'Opened privacy policy');
    Navigator.push<void>(
      context,
      MaterialPageRoute(builder: (_) => const PrivacyPolicyScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final appLockProvider = context.watch<AppLockProvider>();
    final isDark = themeProvider.isDarkMode;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            title: const Text('Settings'),
            pinned: true,
            backgroundColor: scheme.surface,
            foregroundColor: scheme.onSurface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 4,
            shadowColor: scheme.shadow.withValues(alpha: 0.24),
          ),
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final horizontal = AppSpacing.pageHorizontal(
                constraints.crossAxisExtent,
              );
              return SliverPadding(
                padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 40),
                sliver: SliverToBoxAdapter(
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(child: _buildAppHeader(isDark)),
                          const SizedBox(height: AppSpacing.xxl),
                          _buildSectionTitle('Profile', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildProfileSection(isDark),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSectionTitle('Appearance', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildAppearanceSection(themeProvider),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSectionTitle('Security', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildSecuritySection(appLockProvider, isDark),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSectionTitle('Backup & restore', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildBackupSection(isDark),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSectionTitle('Data', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildDataSection(isDark),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSectionTitle('About', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildAboutSection(),
                          if (_developerOptionsUnlocked) ...[
                            const SizedBox(height: AppSpacing.xl),
                            _buildDeveloperOptionsEntry(isDark),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProfileSection(bool isDark) {
    final profile = context.watch<ProfileProvider>();
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurfaceVariant;

    return _buildCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _editDisplayName,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.person_outline, color: secondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      profile.displayName,
                      style: AppTypography.listItem(color: scheme.onSurface)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Used in your CardVault greeting',
                      style: AppTypography.caption(color: secondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.edit_outlined, size: 19, color: secondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return Text(
      title,
      style: AppTypography.sectionTitle(color: scheme.onSurface),
    );
  }

  Widget _buildAppearanceSection(ThemeProvider themeProvider) {
    final appIcon = context.watch<AppIconProvider>().selected;
    final modeLabel = switch (themeProvider.brightnessMode) {
      config.AppBrightnessMode.system => 'System',
      config.AppBrightnessMode.light => 'Light',
      config.AppBrightnessMode.dark => 'Dark',
      config.AppBrightnessMode.amoled => 'OLED black',
    };

    return _buildCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AppearanceScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.palette_outlined,
                color: themeProvider.getSecondaryTextColor(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Appearance',
                      style: AppTypography.listItem(
                        color: themeProvider.getPrimaryTextColor(),
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$modeLabel · ${appIcon.label} icon',
                      style: AppTypography.caption(
                        color: themeProvider.getSecondaryTextColor(),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: themeProvider.seedColor,
                  border: Border.all(
                    color: themeProvider.getOutlineColor(),
                    width: 1.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right,
                color: themeProvider.getSecondaryTextColor(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecuritySection(AppLockProvider appLockProvider, bool isDark) {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    return _buildCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(_getBiometricIcon(), color: scheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lock app when closed',
                        style: AppTypography.listItem(color: scheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Require ${_getBiometricName()} to unlock',
                        style: AppTypography.caption(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: appLockProvider.isAppLockEnabled,
                  onChanged: (value) =>
                      _setAppLockEnabled(appLockProvider, value),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return scheme.onPrimary;
                    }
                    return themeProvider.getSecondaryTextColor();
                  }),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return scheme.primary;
                    }
                    return themeProvider.colorScheme.surfaceContainerHighest;
                  }),
                  trackOutlineColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return Colors.transparent;
                    }
                    return themeProvider.getSecondaryTextColor();
                  }),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSection(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return _buildCard(
      child: Column(
        children: [
          InkWell(
            onTap: _isExporting ? null : _exportBackup,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.upload_file, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Export Backup',
                          style: AppTypography.listItem(
                            color: scheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _lastBackupDate == null
                              ? 'Last backup: Never'
                              : 'Last backup: ${_formatDate(_lastBackupDate!)}',
                          style: AppTypography.caption(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isExporting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          InkWell(
            onTap: _isImporting ? null : _importBackup,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.download, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Import Backup',
                      style: AppTypography.listItem(color: scheme.onSurface),
                    ),
                  ),
                  if (_isImporting)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.arrow_forward_ios,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppHeader(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    final primary = scheme.onSurface;
    final secondary = scheme.onSurfaceVariant;
    final appIcon = context.watch<AppIconProvider>().selected;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIconArtwork(
          option: appIcon,
          size: 82,
          borderRadius: 22,
          addSurfaceShadow: true,
        ),
        const SizedBox(height: 12),
        Text(
          'CardVault',
          style: AppTypography.appBarTitle(color: primary)
              .copyWith(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 2),
        InkWell(
          key: const ValueKey('app-version-developer-unlock'),
          borderRadius: BorderRadius.circular(99),
          onTap: _handleVersionTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Text(
              'Version ${_appVersion.isEmpty ? '1.2.1' : _appVersion}',
              style: AppTypography.caption(color: secondary),
            ),
          ),
        ),
        const SizedBox(height: 14),
        _buildHeaderLinks(),
      ],
    );
  }

  Widget _buildHeaderLinks() {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 400),
      child: Row(
        key: const ValueKey('about-links-row'),
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _buildHeaderLink(
              key: const ValueKey('github-repository-link'),
              label: 'GitHub',
              backgroundColor: const Color(0xFF24292F),
              icon: SvgPicture.asset(
                'assets/branding/github-mark.svg',
                key: const ValueKey('github-logo'),
                width: 25,
                height: 25,
              ),
              onTap: () => _openExternalLink(_repositoryUrl, 'GitHub'),
            ),
          ),
          Expanded(
            child: _buildHeaderLink(
              key: const ValueKey('telegram-link'),
              label: 'Telegram',
              backgroundColor: const Color(0xFF229ED9),
              icon: const Icon(Icons.telegram, size: 25, color: Colors.white),
              onTap: () => _openExternalLink(_telegramUrl, 'Telegram'),
            ),
          ),
          Expanded(
            child: _buildHeaderLink(
              key: const ValueKey('buy-me-a-coffee-link'),
              label: 'Coffee',
              backgroundColor: const Color(0xFFFFDD00),
              icon: const Icon(
                Icons.coffee_rounded,
                size: 25,
                color: Color(0xFF1A1A1A),
              ),
              onTap: () =>
                  _openExternalLink(_buyMeACoffeeUrl, 'Buy Me a Coffee'),
            ),
          ),
          Expanded(
            child: _buildHeaderLink(
              key: const ValueKey('buy-me-a-chai-link'),
              label: 'Chai',
              backgroundColor: const Color(0xFFDE6B35),
              icon: const Icon(
                Icons.emoji_food_beverage_rounded,
                size: 25,
                color: Colors.white,
              ),
              onTap: () => _openExternalLink(_buyMeAChaiUrl, 'Buy Me a Chai'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderLink({
    required Key key,
    required String label,
    required Color backgroundColor,
    required Widget icon,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: 'Open $label',
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: icon,
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                textAlign: TextAlign.center,
                style: AppTypography.caption(color: scheme.onSurface)
                    .copyWith(fontWeight: FontWeight.w600, fontSize: 11),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDeveloperOptionsEntry(bool isDark) {
    final scheme = Theme.of(context).colorScheme;
    return _buildCard(
      child: InkWell(
        key: const ValueKey('developer-options-entry'),
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final disabled = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const DeveloperOptionsScreen()),
          );
          if (disabled == true && mounted) {
            final preferences = await SharedPreferences.getInstance();
            await preferences.setBool(_developerOptionsEnabledKey, false);
            DebugLogger.setEnabled(false);
            AppLogService.instance.action(
              'Settings',
              'Developer options disabled',
            );
            if (!mounted) return;
            setState(() {
              _developerOptionsUnlocked = false;
              _versionTapCount = 0;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Developer options turned off')),
            );
          }
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                Icons.developer_mode_outlined,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Developer options',
                  style: AppTypography.listItem(color: scheme.onSurface)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataSection(bool isDark) {
    final enabled = _cardCount > 0 && !_isDeletingAll;
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurfaceVariant;

    return _buildCard(
      child: InkWell(
        key: const ValueKey('delete-all-cards'),
        borderRadius: BorderRadius.circular(16),
        onTap: enabled ? _deleteAllCards : null,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.delete_sweep_outlined, color: scheme.error),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Delete all cards',
                      style: AppTypography.listItem(
                        color: enabled ? scheme.error : secondary,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _cardCount == 0
                          ? 'No saved cards'
                          : 'Permanently delete $_cardCount card${_cardCount == 1 ? '' : 's'}',
                      style: AppTypography.caption(color: secondary),
                    ),
                  ],
                ),
              ),
              if (_isDeletingAll)
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right, color: secondary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutSection() {
    return _buildCard(
      child: Column(
        children: [
          _buildAboutRow(
            key: const ValueKey('privacy-policy-link'),
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy policy',
            subtitle: 'How CardVault handles your data',
            trailingIcon: Icons.chevron_right,
            onTap: _showPrivacyPolicy,
          ),
          const Divider(height: 1),
          _buildAboutRow(
            key: const ValueKey('open-source-licenses-link'),
            icon: Icons.article_outlined,
            title: 'Open-source licenses',
            subtitle: 'Libraries and licenses used by CardVault',
            trailingIcon: Icons.chevron_right,
            onTap: _showOpenSourceLicenses,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutRow({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required IconData trailingIcon,
    required VoidCallback onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final secondary = scheme.onSurfaceVariant;

    return InkWell(
      key: key,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: secondary),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.listItem(color: scheme.onSurface)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: AppTypography.caption(color: secondary),
                  ),
                ],
              ),
            ),
            Icon(trailingIcon, size: 19, color: secondary),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: AppShapes.largeRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  String _formatDate(String isoDate) {
    try {
      final date = DateTime.parse(isoDate);
      final now = DateTime.now();
      final difference = now.difference(date);

      if (difference.inDays == 0) {
        return 'Today';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} days ago';
      } else {
        return '${date.day}/${date.month}/${date.year}';
      }
    } catch (e) {
      return isoDate;
    }
  }
}

class _EditDisplayNameDialog extends StatefulWidget {
  const _EditDisplayNameDialog({required this.initialName});

  final String initialName;

  @override
  State<_EditDisplayNameDialog> createState() => _EditDisplayNameDialogState();
}

class _EditDisplayNameDialogState extends State<_EditDisplayNameDialog> {
  late final TextEditingController _controller;

  bool get _canSave => _controller.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    if (_canSave) {
      Navigator.pop(context, _controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Your name'),
      content: TextField(
        key: const ValueKey('display-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 40,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Display name',
          prefixIcon: Icon(Icons.person_outline),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          key: const ValueKey('display-name-cancel'),
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const ValueKey('display-name-save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
