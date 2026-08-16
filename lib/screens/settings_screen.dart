import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/theme_provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/profile_provider.dart';
import '../services/secure_card_storage.dart';
import '../services/auth_service.dart';
import '../models/theme_config.dart' as config;

import 'package:package_info_plus/package_info_plus.dart';

import '../theme/app_typography.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../widgets/backup_password_dialog.dart';
import 'appearance_screen.dart';
import 'ai_scan_settings_screen.dart';
import 'developer_options_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SecureCardStorage _cardStorage = SecureCardStorage();
  final AuthService _authService = AuthService();
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
    _loadData();
  }

  Future<void> _loadData() async {
    final lastBackup = await _cardStorage.getLastBackupDate();
    final count = await _cardStorage.getCardCount();
    final biometrics = await _authService.getAvailableBiometrics();

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

      if (mounted) {
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

  void _handleVersionTap() {
    if (_developerOptionsUnlocked) return;
    final taps = _versionTapCount + 1;
    if (taps >= 5) {
      setState(() {
        _versionTapCount = 5;
        _developerOptionsUnlocked = true;
      });
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

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final appLockProvider = context.watch<AppLockProvider>();
    final isDark = themeProvider.isDarkMode;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(title: Text('Settings')),
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
                          _buildSectionTitle('Smart scan', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildSmartScanSection(isDark),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSectionTitle('Backup & restore', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildBackupSection(isDark),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSectionTitle('Data', isDark),
                          const SizedBox(height: AppSpacing.sm),
                          _buildDataSection(isDark),
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
                      modeLabel,
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
                  onChanged: (value) {
                    appLockProvider.setAppLockEnabled(value);
                  },
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

  Widget _buildSmartScanSection(bool isDark) {
    final themeProvider = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final secondary = themeProvider.getSecondaryTextColor();
    return _buildCard(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AiScanSettingsScreen()),
          );
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.auto_awesome_outlined, color: secondary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Smart AI scan',
                      style: AppTypography.listItem(color: scheme.onSurface)
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Providers, saved keys, and encrypted scan logs',
                      style: AppTypography.caption(color: secondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: secondary),
            ],
          ),
        ),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 82,
          height: 82,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: 0.16),
                blurRadius: 18,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Image.asset(
            'assets/branding/cardvault_icon.png',
            fit: BoxFit.cover,
          ),
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
      ],
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
