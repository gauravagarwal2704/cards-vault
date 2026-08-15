import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:share_plus/share_plus.dart';
import '../providers/theme_provider.dart';
import '../providers/app_lock_provider.dart';
import '../services/secure_card_storage.dart';
import '../services/auth_service.dart';
import '../models/theme_config.dart' as config;
import 'package:package_info_plus/package_info_plus.dart';
import '../theme/app_typography.dart';
import '../widgets/backup_password_dialog.dart';
import 'appearance_screen.dart';

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
  String? _lastBackupDate;
  int _cardCount = 0;
  String _appVersion = '';
  List<BiometricType> _availableBiometrics = [];

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
      setState(() {
        _lastBackupDate = lastBackup;
        _cardCount = count;
        _appVersion = packageInfo.version;
        _availableBiometrics = biometrics;
      });
    } catch (e) {
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
            style: TextButton.styleFrom(foregroundColor: Colors.red),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Backup saved to:\n$filePath'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Share',
              textColor: Colors.white,
              onPressed: () => Share.shareXFiles(
                [XFile(filePath)],
                subject: 'Cards Wallet backup',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Export failed: $e'),
            backgroundColor: Colors.red,
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mode == BackupImportMode.replace
                  ? 'Replaced your cards with $importedCount from the backup'
                  : 'Successfully imported $importedCount cards',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Import failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isImporting = false);
      }
    }
  }

  Future<void> _testAuthentication() async {
    final authenticated = await _authService.authenticateForCardDetails();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            authenticated ? 'Authentication successful!' : 'Authentication failed',
          ),
          backgroundColor: authenticated ? Colors.green : Colors.red,
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
      backgroundColor: themeProvider.getBackgroundColor(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back,
            color: themeProvider.getPrimaryTextColor(),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Settings',
          style: AppTypography.appBarTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('Appearance', isDark),
            const SizedBox(height: 12),
            _buildAppearanceSection(themeProvider),
            const SizedBox(height: 24),
            _buildSectionTitle('Security', isDark),
            const SizedBox(height: 12),
            _buildSecuritySection(appLockProvider, isDark),
            const SizedBox(height: 24),
            _buildSectionTitle('Backup & Restore', isDark),
            const SizedBox(height: 12),
            _buildBackupSection(isDark),
            const SizedBox(height: 24),
            _buildSectionTitle('About', isDark),
            const SizedBox(height: 12),
            _buildAboutSection(isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDark) {
    return Text(
      title,
      style: AppTypography.sectionTitle(
        color: isDark ? Colors.white : Colors.black87,
      ),
    );
  }

  Widget _buildAppearanceSection(ThemeProvider themeProvider) {
    final modeLabel = switch (themeProvider.brightnessMode) {
      config.AppBrightnessMode.light => 'Light',
      config.AppBrightnessMode.dark => 'Dark',
      config.AppBrightnessMode.amoled => 'AMOLED',
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
    return _buildCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  _getBiometricIcon(),
                  color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lock app when closed',
                        style: AppTypography.listItem(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Require ${_getBiometricName()} to unlock',
                        style: AppTypography.caption(
                          color: isDark ? const Color(0xFFB0B0B0) : Colors.black54,
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
                      return Colors.white;
                    }
                    return themeProvider.getSecondaryTextColor();
                  }),
                  trackColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return themeProvider.seedColor;
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
          const Divider(height: 1),
          InkWell(
            onTap: _testAuthentication,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.security,
                    color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Test Authentication',
                      style: AppTypography.listItem(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 16,
                    color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade400,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupSection(bool isDark) {
    return _buildCard(
      child: Column(
        children: [
          InkWell(
            onTap: _isExporting ? null : _exportBackup,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.upload_file,
                    color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Export Backup',
                      style: AppTypography.listItem(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
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
                      color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade400,
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
                  Icon(
                    Icons.download,
                    color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Import Backup',
                      style: AppTypography.listItem(
                        color: isDark ? Colors.white : Colors.black87,
                      ),
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
                      color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade400,
                    ),
                ],
              ),
            ),
          ),
          if (_lastBackupDate != null) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.access_time,
                    color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Last Backup',
                          style: AppTypography.listItem(
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatDate(_lastBackupDate!),
                          style: AppTypography.caption(
                            color: isDark ? const Color(0xFFB0B0B0) : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAboutSection(bool isDark) {
    return _buildCard(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'App Version',
                        style: AppTypography.listItem(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _appVersion.isEmpty ? '1.0.0' : _appVersion,
                        style: AppTypography.caption(
                          color: isDark ? const Color(0xFFB0B0B0) : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  Icons.credit_card,
                  color: isDark ? const Color(0xFFB0B0B0) : Colors.grey.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Stored Cards',
                        style: AppTypography.listItem(
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$_cardCount card${_cardCount != 1 ? 's' : ''}',
                        style: AppTypography.caption(
                          color: isDark ? const Color(0xFFB0B0B0) : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    final themeProvider = context.watch<ThemeProvider>();
    
    return Container(
      decoration: BoxDecoration(
        color: themeProvider.getCardColor(),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
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
