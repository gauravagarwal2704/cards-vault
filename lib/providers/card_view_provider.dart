import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/app_log_service.dart';

enum CardViewMode { carousel, stackedGrid }

extension CardViewModeDisplay on CardViewMode {
  String get label {
    switch (this) {
      case CardViewMode.carousel:
        return 'Carousel';
      case CardViewMode.stackedGrid:
        return 'Stacks';
    }
  }

  IconData get icon {
    switch (this) {
      case CardViewMode.carousel:
        return Icons.view_carousel_outlined;
      case CardViewMode.stackedGrid:
        return Icons.dashboard_outlined;
    }
  }
}

/// The attribute that decides which cards share a stack in
/// [CardViewMode.stackedGrid].
enum CardStackBy { none, bank, type, cardholder, custom }

extension CardStackByDisplay on CardStackBy {
  String get label {
    switch (this) {
      case CardStackBy.none:
        return 'No grouping';
      case CardStackBy.bank:
        return 'Bank';
      case CardStackBy.type:
        return 'Type';
      case CardStackBy.cardholder:
        return 'Cardholder';
      case CardStackBy.custom:
        return 'Custom';
    }
  }

  IconData get icon {
    switch (this) {
      case CardStackBy.none:
        return Icons.grid_view_outlined;
      case CardStackBy.bank:
        return Icons.account_balance_outlined;
      case CardStackBy.type:
        return Icons.credit_card_outlined;
      case CardStackBy.cardholder:
        return Icons.person_outline;
      case CardStackBy.custom:
        return Icons.folder_outlined;
    }
  }
}

class CardViewProvider extends ChangeNotifier {
  static const String _viewModeKey = 'card_view_mode';
  static const String _stackByKey = 'card_stack_by';

  /// The grouped grid shipped before stacks existed and only ever grouped by
  /// custom group, so it maps onto the stacked grid on the custom axis.
  static const String _legacyGroupedGridValue = 'groupedGrid';
  static const String _legacyGridValue = 'grid';

  CardViewMode _viewMode = CardViewMode.carousel;
  CardStackBy _stackBy = CardStackBy.none;

  CardViewProvider() {
    _loadPreferences();
  }

  CardViewMode get viewMode => _viewMode;
  CardStackBy get stackBy => _stackBy;

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedMode = prefs.getString(_viewModeKey);
      CardStackBy? migratedStackBy;
      if (savedMode != null) {
        if (savedMode == _legacyGridValue) {
          _viewMode = CardViewMode.stackedGrid;
          migratedStackBy = CardStackBy.none;
        } else if (savedMode == _legacyGroupedGridValue) {
          _viewMode = CardViewMode.stackedGrid;
          migratedStackBy = CardStackBy.custom;
        } else {
          _viewMode = CardViewMode.values.firstWhere(
            (mode) => mode.name == savedMode,
            orElse: () => CardViewMode.carousel,
          );
        }
      }

      final savedStackBy = prefs.getString(_stackByKey);
      if (migratedStackBy != null) {
        _stackBy = migratedStackBy;
        await prefs.setString(_viewModeKey, CardViewMode.stackedGrid.name);
        await prefs.setString(_stackByKey, migratedStackBy.name);
      } else if (savedStackBy != null) {
        _stackBy = CardStackBy.values.firstWhere(
          (axis) => axis.name == savedStackBy,
          orElse: () => CardStackBy.none,
        );
      }

      notifyListeners();
    } catch (e, stackTrace) {
      AppLogService.instance.recordFailure(
        'Load wallet view preferences',
        e,
        stackTrace,
        category: 'Failure/Preferences',
      );
      debugPrint('Error loading card view preferences: $e');
    }
  }

  Future<void> setViewMode(CardViewMode mode) async {
    if (_viewMode == mode) return;
    _viewMode = mode;
    notifyListeners();
    AppLogService.instance.action(
      'Cards',
      'Wallet view changed',
      details: {'mode': mode.name},
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewModeKey, mode.name);
    } catch (e, stackTrace) {
      AppLogService.instance.recordFailure(
        'Save wallet view preference',
        e,
        stackTrace,
        category: 'Failure/Preferences',
      );
      debugPrint('Error saving card view mode: $e');
    }
  }

  Future<void> setStackBy(CardStackBy axis) async {
    if (_stackBy == axis) return;
    _stackBy = axis;
    notifyListeners();
    AppLogService.instance.action(
      'Cards',
      'Card grouping changed',
      details: {'axis': axis.name},
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stackByKey, axis.name);
    } catch (e, stackTrace) {
      AppLogService.instance.recordFailure(
        'Save card grouping preference',
        e,
        stackTrace,
        category: 'Failure/Preferences',
      );
      debugPrint('Error saving card stack axis: $e');
    }
  }

  Future<void> cycleViewMode() {
    final next =
        CardViewMode.values[(_viewMode.index + 1) % CardViewMode.values.length];
    return setViewMode(next);
  }
}
