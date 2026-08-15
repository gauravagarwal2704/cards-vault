import 'dart:io';

import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';
import 'package:provider/provider.dart';

import '../providers/nfc_provider.dart';
import '../providers/theme_provider.dart';
import '../theme/app_typography.dart';

/// Checks whether an NFC scan can start. When it cannot, explains why — offering
/// a shortcut to the system NFC settings if it is merely switched off — and
/// returns false. The NFC option stays visible either way so users are told what
/// is wrong instead of silently losing the entry point.
Future<bool> ensureNfcReady(BuildContext context) async {
  final nfcProvider = context.read<NfcProvider>();

  // Card reading relies on Android APDU access; iOS is unsupported regardless of
  // what the platform reports about NFC hardware.
  if (Platform.isIOS) {
    await _showMessage(
      context,
      title: 'NFC Not Supported',
      message:
          'Reading cards over NFC is not supported on iPhone. Use Scan Card or Add Manually instead.',
    );
    return false;
  }

  await nfcProvider.checkNfcAvailability();
  if (!context.mounted) return false;

  switch (nfcProvider.availability) {
    case NFCAvailability.available:
      return true;
    case NFCAvailability.disabled:
      await _showMessage(
        context,
        title: 'NFC Is Turned Off',
        message:
            'Turn on NFC in your device settings to scan a card by tapping it.',
        onOpenSettings: () => AppSettings.openAppSettings(
          type: AppSettingsType.nfc,
        ),
      );
      return false;
    case NFCAvailability.not_supported:
      await _showMessage(
        context,
        title: 'NFC Not Supported',
        message:
            'This device does not have NFC hardware. Use Scan Card or Add Manually instead.',
      );
      return false;
  }
}

Future<void> _showMessage(
  BuildContext context, {
  required String title,
  required String message,
  VoidCallback? onOpenSettings,
}) {
  final themeProvider = context.read<ThemeProvider>();

  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: themeProvider.getCardColor(),
      title: Row(
        children: [
          Icon(
            Icons.contactless_outlined,
            color: themeProvider.getPrimaryColor(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppTypography.dialogTitle(
                color: themeProvider.getPrimaryTextColor(),
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: AppTypography.body(
          color: themeProvider.getSecondaryTextColor(),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(onOpenSettings == null ? 'OK' : 'Not now'),
        ),
        if (onOpenSettings != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              onOpenSettings();
            },
            child: const Text('Open settings'),
          ),
      ],
    ),
  );
}
