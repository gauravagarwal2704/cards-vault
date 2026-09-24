import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/support_email_service.dart';
import '../services/app_log_service.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';

class FeedbackSupportScreen extends StatefulWidget {
  const FeedbackSupportScreen({
    super.key,
    this.sendFeedback,
    this.downloadLogs,
  });

  final Future<void> Function(
    SupportFeedbackType type,
    String comments,
    bool includeDiagnostics,
  )?
  sendFeedback;
  final Future<bool> Function()? downloadLogs;

  @override
  State<FeedbackSupportScreen> createState() => _FeedbackSupportScreenState();
}

class _FeedbackSupportScreenState extends State<FeedbackSupportScreen> {
  final TextEditingController _commentsController = TextEditingController();
  SupportFeedbackType _type = SupportFeedbackType.bugReport;
  bool _includeDiagnostics = true;
  bool _sending = false;
  bool _downloadingLogs = false;

  @override
  void initState() {
    super.initState();
    AppLogService.instance.action('Navigation', 'Opened Feedback & Support');
    _commentsController.addListener(_commentsChanged);
  }

  @override
  void dispose() {
    _commentsController
      ..removeListener(_commentsChanged)
      ..dispose();
    super.dispose();
  }

  void _commentsChanged() => setState(() {});

  Future<void> _send() async {
    final comments = _commentsController.text.trim();
    if (comments.isEmpty || _sending) return;
    setState(() => _sending = true);
    AppLogService.instance.action(
      'Support',
      'Feedback email requested',
      details: {'type': _type.name, 'includeDiagnostics': _includeDiagnostics},
    );
    try {
      if (widget.sendFeedback case final callback?) {
        await callback(_type, comments, _includeDiagnostics);
      } else {
        await SupportEmailService().sendFeedback(
          type: _type,
          comments: comments,
          includeDiagnostics: _includeDiagnostics,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Email draft opened')));
    } catch (error) {
      AppLogService.instance.record(
        'Support',
        'Feedback email could not be opened: $error',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not open an email app'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _downloadLogs() async {
    if (_downloadingLogs || _sending) return;
    setState(() => _downloadingLogs = true);
    AppLogService.instance.action('Support', 'Download Logs selected');
    try {
      final callback = widget.downloadLogs;
      final saved = callback != null
          ? await callback()
          : await SupportEmailService().downloadLogs();
      if (!mounted || !saved) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Diagnostic logs saved')));
    } catch (error, stackTrace) {
      AppLogService.instance.recordFailure(
        'Save diagnostic logs',
        error,
        stackTrace,
        category: 'Failure/Support',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Could not save diagnostic logs'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloadingLogs = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.watch<ThemeProvider>();
    final scheme = Theme.of(context).colorScheme;
    final primary = theme.getPrimaryTextColor();
    final secondary = theme.getSecondaryTextColor();
    final canSend = _commentsController.text.trim().isNotEmpty && !_sending;

    return Scaffold(
      backgroundColor: theme.getBackgroundColor(),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Feedback & Support',
          style: AppTypography.appBarTitle(color: primary),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.xxxl,
        ),
        children: [
          Text(
            'Write to us directly',
            style: AppTypography.sectionTitle(color: primary)
                .copyWith(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Feedback Type',
            style: AppTypography.listItem(color: primary)
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<SupportFeedbackType>(
            key: const ValueKey('feedback-type-field'),
            initialValue: _type,
            decoration: const InputDecoration(),
            items: SupportFeedbackType.values
                .map(
                  (type) =>
                      DropdownMenuItem(value: type, child: Text(type.label)),
                )
                .toList(growable: false),
            onChanged: _sending
                ? null
                : (type) {
                    if (type != null) setState(() => _type = type);
                  },
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Message',
            style: AppTypography.listItem(color: primary)
                .copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            key: const ValueKey('feedback-comments-field'),
            controller: _commentsController,
            enabled: !_sending,
            minLines: 6,
            maxLines: 10,
            maxLength: 4000,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'Describe your request or issue in detail…',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          CheckboxListTile(
            key: const ValueKey('attach-diagnostics-checkbox'),
            value: _includeDiagnostics,
            onChanged: _sending
                ? null
                : (value) =>
                      setState(() => _includeDiagnostics = value ?? true),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.trailing,
            title: Text(
              'Attach Debug Logs & Device Info',
              style: AppTypography.listItem(color: primary),
            ),
            subtitle: Text(
              'Includes generic app logs and device details. No sensitive financial data is shared.',
              style: AppTypography.caption(color: secondary),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const ValueKey('download-diagnostic-logs-button'),
              onPressed: _sending || _downloadingLogs ? null : _downloadLogs,
              icon: _downloadingLogs
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.download_outlined),
              label: Text(
                _downloadingLogs ? 'Preparing Logs…' : 'Download Logs (.txt)',
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          SizedBox(
            height: 54,
            child: FilledButton(
              key: const ValueKey('send-feedback-button'),
              onPressed: canSend ? _send : null,
              child: _sending
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Send Feedback'),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            'Your default email app will open with the recipient, subject, message, and optional diagnostics ready to review.',
            textAlign: TextAlign.center,
            style: AppTypography.caption(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
