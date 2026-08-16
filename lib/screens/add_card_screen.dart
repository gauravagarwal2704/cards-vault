import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/card_data.dart';
import '../providers/nfc_provider.dart';
import '../services/ocr_service.dart';
import '../services/secure_card_storage.dart';
import '../theme/app_colors.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_design_system.dart';
import 'card_camera_screen.dart';
import 'card_edit_screen.dart';
import 'manual_add_card_screen.dart';
import 'nfc_scan_screen.dart';

/// A single entry point for every card-capture method.
///
/// The screen deliberately describes capabilities before asking the user to
/// choose. Camera remains the recommended path, while unavailable NFC is
/// explained instead of disappearing unexpectedly.
class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key});

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  final SecureCardStorage _cardStorage = SecureCardStorage();
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NfcProvider>().checkNfcAvailability();
    });
  }

  Future<void> _scanWithCamera() async {
    final result = await Navigator.push<OCRResult>(
      context,
      MaterialPageRoute(builder: (_) => const CardCameraScreen()),
    );
    if (result == null || !mounted) return;

    final card = await Navigator.push<CardData>(
      context,
      MaterialPageRoute(builder: (_) => CardEditScreen(ocrResult: result)),
    );
    if (card == null || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _cardStorage.saveCard(card);
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save the card: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  Future<void> _scanWithNfc() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const NfcScanScreen()),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  Future<void> _addManually() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ManualAddCardScreen()),
    );
    if (result == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = AppSemanticColors.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Add a card')),
      body: Consumer<NfcProvider>(
        builder: (context, nfc, _) {
          final checking = nfc.state == NfcState.checking;
          final nfcAvailable = !Platform.isIOS && nfc.isNfcEnabled;
          final nfcSupported = !Platform.isIOS && nfc.isNfcSupported;

          return SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = AppSpacing.pageHorizontal(
                  constraints.maxWidth,
                );
                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    horizontal,
                    AppSpacing.lg,
                    horizontal,
                    AppSpacing.xxl,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 720),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'How would you like to add it?',
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Your card details stay encrypted on this device.',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          _CaptureOption(
                            icon: Icons.document_scanner_outlined,
                            title: 'Scan with camera',
                            subtitle: 'Fastest · review every detected detail before saving',
                            badge: 'Recommended',
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            onTap: _isSaving ? null : _scanWithCamera,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _CaptureOption(
                            icon: Icons.nfc_rounded,
                            title: 'Tap with NFC',
                            subtitle: checking
                                ? 'Checking this device…'
                                : nfcAvailable
                                ? 'Hold a contactless card against your phone'
                                : Platform.isIOS
                                ? 'Card reading is not supported on iOS'
                                : nfcSupported
                                ? 'NFC is turned off'
                                : 'NFC hardware is not available',
                            trailing: checking
                                ? const SizedBox.square(
                                    dimension: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : null,
                            enabled: nfcAvailable && !_isSaving,
                            backgroundColor: scheme.secondaryContainer,
                            foregroundColor: scheme.onSecondaryContainer,
                            onTap: _scanWithNfc,
                          ),
                          if (!checking && nfcSupported && !nfcAvailable) ...[
                            const SizedBox(height: AppSpacing.sm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: () => AppSettings.openAppSettings(
                                  type: AppSettingsType.nfc,
                                ),
                                icon: const Icon(Icons.settings_outlined),
                                label: const Text('Open NFC settings'),
                              ),
                            ),
                          ],
                          const SizedBox(height: AppSpacing.md),
                          _CaptureOption(
                            icon: Icons.edit_note_rounded,
                            title: 'Enter details manually',
                            subtitle:
                                'Best for virtual cards or cards without NFC',
                            backgroundColor: scheme.tertiaryContainer,
                            foregroundColor: scheme.onTertiaryContainer,
                            onTap: _isSaving ? null : _addManually,
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                          AppStatusMessage(
                            kind: AppStatusKind.privacy,
                            title: 'Private by design',
                            message: 'Camera images are processed for review and discarded. Card data is stored encrypted.',
                            icon: Icons.enhanced_encryption_outlined,
                          ),
                          if (_isSaving) ...[
                            const SizedBox(height: AppSpacing.md),
                            AppStatusMessage(
                              kind: AppStatusKind.success,
                              title: 'Securing your card',
                              message: 'Encrypting and saving on this device…',
                              icon: Icons.lock_clock_outlined,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Camera and NFC availability depend on your device.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: semantic.onPrivacyContainer),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _CaptureOption extends StatelessWidget {
  const _CaptureOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.onTap,
    this.badge,
    this.trailing,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String? badge;
  final Widget? trailing;
  final Color backgroundColor;
  final Color foregroundColor;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      onTap: enabled ? onTap : null,
      color: enabled ? backgroundColor : scheme.surfaceContainerLow,
      foregroundColor: enabled ? foregroundColor : scheme.onSurfaceVariant,
      shape: AppShapes.extraLarge,
      semanticLabel: '$title. $subtitle',
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: (enabled ? foregroundColor : scheme.onSurfaceVariant)
                    .withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 28),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.xs,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                            vertical: AppSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: foregroundColor.withValues(alpha: 0.12),
                            borderRadius: AppShapes.pillRadius,
                          ),
                          child: Text(
                            badge!,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: enabled
                          ? foregroundColor.withValues(alpha: 0.78)
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            trailing ?? const Icon(Icons.arrow_forward_rounded),
          ],
        ),
      ),
    );
  }
}
