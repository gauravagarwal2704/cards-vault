import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/theme_provider.dart';
import '../services/ai_scan_log_service.dart';
import '../theme/app_typography.dart';
import '../theme/app_colors.dart';

class AiScanLogsScreen extends StatefulWidget {
  const AiScanLogsScreen({super.key});

  @override
  State<AiScanLogsScreen> createState() => _AiScanLogsScreenState();
}

class _AiScanLogsScreenState extends State<AiScanLogsScreen> {
  final _logService = AiScanLogService();
  List<AiScanLogEntry> _logs = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final logs = await _logService.load();
    if (!mounted) return;
    setState(() {
      _logs = logs;
      _loading = false;
    });
  }

  Future<void> _clearLogs() async {
    if (_logs.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete SmartAI scan logs?'),
        content: Text(
          'Permanently delete ${_logs.length} encrypted log${_logs.length == 1 ? '' : 's'} from this device?',
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
            child: const Text('Delete logs'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _logService.clear();
    if (!mounted) return;
    setState(() => _logs = const []);
  }

  Future<void> _showLog(AiScanLogEntry entry) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.receipt_long_outlined),
        title: Text('${entry.provider.label} scan log'),
        content: SizedBox(
          width: 600,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.model} · ${_formatDate(entry.createdAt)}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                SelectableText(entry.endpoint),
                const SizedBox(height: 4),
                Text(
                  entry.httpStatus == null
                      ? 'No HTTP status · ${entry.message}'
                      : 'HTTP ${entry.httpStatus} · ${entry.message}',
                ),
                const SizedBox(height: 18),
                const Text(
                  'Request summary',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(entry.requestSummary),
                const SizedBox(height: 14),
                const Text(
                  'Request body (image data omitted)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                _codeBlock(dialogContext, entry.requestBody),
                if (entry.validationSummary != null) ...[
                  const SizedBox(height: 18),
                  const Text(
                    'CardVault validation',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 6),
                  Text(entry.validationSummary!),
                ],
                const SizedBox(height: 18),
                const Text(
                  'Provider response',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                const Text(
                  'May contain the full card number. API credentials are redacted.',
                ),
                const SizedBox(height: 8),
                _codeBlock(dialogContext, entry.responseBody),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _codeBlock(BuildContext context, String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final local = date.toLocal();
    String twoDigits(int value) => value.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)}';
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
          'SmartAI scan logs',
          style: AppTypography.appBarTitle(color: primary),
        ),
        actions: [
          if (_logs.isNotEmpty)
            IconButton(
              tooltip: 'Delete all logs',
              onPressed: _clearLogs,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _logs.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 48,
                      color: secondary,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'No SmartAI scan logs yet',
                      style: AppTypography.listItem(color: primary)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Provider responses will appear here after an AI-assisted scan.',
                      textAlign: TextAlign.center,
                      style: AppTypography.body(color: secondary),
                    ),
                  ],
                ),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              itemCount: _logs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = _logs[index];
                final semantic = AppSemanticColors.of(context);
                final statusColor = entry.succeeded
                    ? semantic.success
                    : Theme.of(context).colorScheme.error;
                return Material(
                  color: theme.getCardColor(),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.getOutlineColor()),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ListTile(
                    onTap: () => _showLog(entry),
                    leading: CircleAvatar(
                      backgroundColor: statusColor.withValues(alpha: 0.12),
                      child: Icon(
                        entry.succeeded
                            ? Icons.check_circle_outline
                            : Icons.error_outline,
                        color: statusColor,
                      ),
                    ),
                    title: Text(
                      '${entry.provider.label} · ${entry.httpStatus == null ? 'No response' : 'HTTP ${entry.httpStatus}'}',
                      style: AppTypography.body(color: primary)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${_formatDate(entry.createdAt)}\n${entry.message}',
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(color: secondary),
                    ),
                    isThreeLine: true,
                    trailing: Icon(Icons.chevron_right, color: secondary),
                  ),
                );
              },
            ),
    );
  }
}
