import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/card_group.dart';
import '../providers/theme_provider.dart';
import '../services/card_group_storage.dart';
import '../theme/app_typography.dart';

/// Wraps the picker outcome so "cleared the group" (`group == null`) can be told
/// apart from "dismissed the sheet" (a null result).
class GroupSelection {
  final CardGroup? group;
  const GroupSelection(this.group);
}

Future<GroupSelection?> showGroupPickerSheet(
  BuildContext context, {
  String? selectedGroupId,
}) {
  return showModalBottomSheet<GroupSelection>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _GroupPickerSheet(selectedGroupId: selectedGroupId),
  );
}

/// Asks for a group name in a keyboard-aware bottom sheet. Returns null when
/// dismissed, so callers can tell a cancel apart from an empty name.
Future<String?> showGroupNameSheet(
  BuildContext context, {
  required String title,
  String? initialValue,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) =>
        _GroupNameSheet(title: title, initialValue: initialValue),
  );
}

class _GroupNameSheet extends StatefulWidget {
  final String title;
  final String? initialValue;

  const _GroupNameSheet({required this.title, this.initialValue});

  @override
  State<_GroupNameSheet> createState() => _GroupNameSheetState();
}

class _GroupNameSheetState extends State<_GroupNameSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );

  bool get _canSave => _controller.text.trim().isNotEmpty;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: themeProvider.getCardColor(),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: themeProvider.getSecondaryTextColor().withValues(
                        alpha: 0.35,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  widget.title,
                  style: AppTypography.dialogTitle(
                    color: themeProvider.getPrimaryTextColor(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  key: const ValueKey('group-name-field'),
                  controller: _controller,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  style: AppTypography.body(
                    color: themeProvider.getPrimaryTextColor(),
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Group name',
                    hintText: 'e.g. Airport lounge',
                  ),
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (_) => _save(),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        key: const ValueKey('save-group-name'),
                        onPressed: _canSave ? _save : null,
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupPickerSheet extends StatefulWidget {
  final String? selectedGroupId;

  const _GroupPickerSheet({this.selectedGroupId});

  @override
  State<_GroupPickerSheet> createState() => _GroupPickerSheetState();
}

class _GroupPickerSheetState extends State<_GroupPickerSheet> {
  final CardGroupStorage _groupStorage = CardGroupStorage();
  List<CardGroup> _groups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    final groups = await _groupStorage.loadGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups;
      _isLoading = false;
    });
  }

  Future<void> _createGroup() async {
    final name = await showGroupNameSheet(context, title: 'New Group');
    if (name == null || name.isEmpty) return;

    final group = await _groupStorage.createGroup(name);
    if (!mounted) return;
    Navigator.pop(context, GroupSelection(group));
  }

  Future<void> _renameGroup(CardGroup group) async {
    final name = await showGroupNameSheet(
      context,
      title: 'Rename Group',
      initialValue: group.name,
    );
    if (name == null || name.isEmpty) return;

    await _groupStorage.renameGroup(group.id, name);
    await _loadGroups();
  }

  Future<void> _deleteGroup(CardGroup group) async {
    final themeProvider = context.read<ThemeProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: themeProvider.getCardColor(),
        title: Text(
          'Delete Group?',
          style: AppTypography.dialogTitle(
            color: themeProvider.getPrimaryTextColor(),
          ),
        ),
        content: Text(
          '"${group.name}" will be removed. The cards in it are kept and become ungrouped.',
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
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await _groupStorage.deleteGroup(group.id);
    if (!mounted) return;

    if (widget.selectedGroupId == group.id) {
      Navigator.pop(context, const GroupSelection(null));
      return;
    }
    await _loadGroups();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: themeProvider.getBackgroundColor(),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Group',
                      style: AppTypography.sectionTitle(
                        color: themeProvider.getPrimaryTextColor(),
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _createGroup,
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('New group'),
                  ),
                ],
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 12),
                  children: [
                    _buildOption(
                      label: 'No group',
                      isSelected: widget.selectedGroupId == null,
                      onTap: () =>
                          Navigator.pop(context, const GroupSelection(null)),
                    ),
                    for (final group in _groups)
                      _buildOption(
                        label: group.name,
                        isSelected: widget.selectedGroupId == group.id,
                        onTap: () =>
                            Navigator.pop(context, GroupSelection(group)),
                        trailing: PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_vert,
                            color: themeProvider.getSecondaryTextColor(),
                          ),
                          onSelected: (value) {
                            if (value == 'rename') {
                              _renameGroup(group);
                            } else if (value == 'delete') {
                              _deleteGroup(group);
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'rename',
                              child: Text('Rename'),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete'),
                            ),
                          ],
                        ),
                      ),
                    if (_groups.isEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
                        child: Text(
                          'Create a group to keep cards from the same bank or family together.',
                          style: AppTypography.caption(
                            color: themeProvider.getSecondaryTextColor(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOption({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final themeProvider = context.watch<ThemeProvider>();

    return ListTile(
      onTap: onTap,
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected
            ? themeProvider.getPrimaryColor()
            : themeProvider.getSecondaryTextColor(),
      ),
      title: Text(
        label,
        style: AppTypography.body(color: themeProvider.getPrimaryTextColor()),
      ),
      trailing: trailing,
    );
  }
}

/// Form row that mirrors the bank selector styling and opens the group picker.
class GroupSelectorField extends StatelessWidget {
  final CardGroup? selectedGroup;
  final ValueChanged<CardGroup?> onChanged;

  const GroupSelectorField({
    super.key,
    required this.selectedGroup,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final themeProvider = context.watch<ThemeProvider>();
    final isDark = themeProvider.isDarkMode;

    return GestureDetector(
      onTap: () async {
        final selection = await showGroupPickerSheet(
          context,
          selectedGroupId: selectedGroup?.id,
        );
        if (selection != null) onChanged(selection.group);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.2)
                : const Color(0xFFD1D5DB),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.folder_outlined,
              size: 20,
              color: themeProvider.getSecondaryTextColor(),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                selectedGroup?.name ?? 'No group',
                style: AppTypography.bodyLarge(
                  color: selectedGroup != null
                      ? themeProvider.getPrimaryTextColor()
                      : (isDark ? Colors.grey.shade600 : Colors.grey.shade400),
                ),
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: themeProvider.getSecondaryTextColor(),
            ),
          ],
        ),
      ),
    );
  }
}
