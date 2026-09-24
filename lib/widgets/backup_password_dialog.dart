import 'package:flutter/material.dart';

import '../services/backup_crypto.dart';
import '../theme/app_typography.dart';

/// Asks for the password that protects a `.cwbak` file. Returns null when the
/// user backs out.
Future<String?> promptBackupPassword(
  BuildContext context, {
  required String title,
  required String confirmLabel,
  String? description,
  bool requireConfirm = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (dialogContext) => BackupPasswordDialog(
      title: title,
      confirmLabel: confirmLabel,
      description: description,
      requireConfirm: requireConfirm,
    ),
  );
}

class BackupPasswordDialog extends StatefulWidget {
  final String title;
  final String confirmLabel;
  final String? description;
  final bool requireConfirm;

  const BackupPasswordDialog({
    super.key,
    required this.title,
    required this.confirmLabel,
    this.description,
    this.requireConfirm = false,
  });

  @override
  State<BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<BackupPasswordDialog> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _obscure = true;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, _passwordController.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title, style: AppTypography.dialogTitle()),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              widget.description ??
                  (widget.requireConfirm
                      ? 'Choose a password to encrypt this backup. You will need the same password to import on another phone.'
                      : 'Enter the password used when this backup was exported.'),
              style: AppTypography.label().copyWith(
                fontWeight: FontWeight.w400,
              ),
            ),
            const SizedBox(height: 16),
            if (widget.requireConfirm) ...[
              Text(
                'Use $backupMinimumPasswordLength or more characters. This password cannot be recovered.',
                style: AppTypography.caption().copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextFormField(
              controller: _passwordController,
              obscureText: _obscure,
              autofocus: true,
              onFieldSubmitted: (_) {
                if (!widget.requireConfirm) _submit();
              },
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility,
                  ),
                  onPressed: () {
                    setState(() => _obscure = !_obscure);
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Password is required';
                }
                if (widget.requireConfirm &&
                    value.length < backupMinimumPasswordLength) {
                  return 'At least $backupMinimumPasswordLength characters';
                }
                return null;
              },
            ),
            if (widget.requireConfirm) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscure,
                onFieldSubmitted: (_) => _submit(),
                decoration: const InputDecoration(
                  labelText: 'Confirm password',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  if (value != _passwordController.text) {
                    return 'Passwords do not match';
                  }
                  return null;
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: Text(widget.confirmLabel)),
      ],
    );
  }
}
