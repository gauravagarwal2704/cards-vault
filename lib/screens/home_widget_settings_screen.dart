import 'package:flutter/material.dart';

import '../models/card_data.dart';
import '../services/home_widget_service.dart';

class HomeWidgetSettingsScreen extends StatefulWidget {
  const HomeWidgetSettingsScreen({
    super.key,
    required this.widgetId,
    required this.cards,
  });
  final int widgetId;
  final List<CardData> cards;

  @override
  State<HomeWidgetSettingsScreen> createState() =>
      _HomeWidgetSettingsScreenState();
}

class _HomeWidgetSettingsScreenState extends State<HomeWidgetSettingsScreen> {
  final _selected = <String>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final config = await HomeWidgetService.instance.configuration(
        widget.widgetId,
      );
      if (!mounted) return;
      final available = widget.cards.map((c) => c.id).toSet();
      _selected.addAll(
        (config['ids'] as List? ?? [])
            .whereType<String>()
            .where(available.contains)
            .take(4),
      );
    } catch (_) {
      _error = 'This widget is no longer available. Add it again from your home screen.';
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await HomeWidgetService.instance.save(widget.widgetId, _selected);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save this widget. Please try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Customize widget'),
      actions: [
        TextButton(
          key: const ValueKey('widget-save'),
          onPressed: _loading || _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    ),
    body: _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Choose up to four favorite cards. Selection order controls display order. '
                'All selected cards stay visible as you resize the widget. Card details and backgrounds appear on your home screen, including outside app lock and in screenshots.',
              ),
              const SizedBox(height: 12),
              if (widget.cards.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Add a card in your wallet, then return here.'),
                ),
              for (final card in widget.cards.where((c) => c.id != null))
                CheckboxListTile(
                  title: Text(
                    card.cardNickname?.isNotEmpty == true
                        ? card.cardNickname!
                        : widgetCardSnapshot(card)['bank'] as String,
                  ),
                  subtitle: Text(
                    '•••• ${widgetCardSnapshot(card)['lastFour']}',
                  ),
                  secondary: _selected.contains(card.id)
                      ? CircleAvatar(
                          child: Text('${_selected.indexOf(card.id!) + 1}'),
                        )
                      : null,
                  value: _selected.contains(card.id),
                  onChanged:
                      _saving ||
                          (!_selected.contains(card.id) &&
                              _selected.length >= 4)
                      ? null
                      : (value) => setState(() {
                          if (value == true) {
                            _selected.add(card.id!);
                          } else {
                            _selected.remove(card.id);
                          }
                        }),
                ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(_error!),
                ),
            ],
          ),
  );
}
