import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum CardViewMode {
  carousel,
  grid,
  stackedGrid,
}

extension CardViewModeDisplay on CardViewMode {
  String get label {
    switch (this) {
      case CardViewMode.carousel:
        return 'Carousel';
      case CardViewMode.grid:
        return 'Grid';
      case CardViewMode.stackedGrid:
        return 'Stacked grid';
    }
  }

  IconData get icon {
    switch (this) {
      case CardViewMode.carousel:
        return Icons.view_carousel_outlined;
      case CardViewMode.grid:
        return Icons.grid_view_outlined;
      case CardViewMode.stackedGrid:
        return Icons.dashboard_outlined;
    }
  }
}

/// The attribute that decides which cards share a stack in
/// [CardViewMode.stackedGrid].
enum CardStackBy {
  bank,
  type,
  cardholder,
  custom,
}

extension CardStackByDisplay on CardStackBy {
  String get label {
    switch (this) {
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

  CardViewMode _viewMode = CardViewMode.carousel;
  CardStackBy _stackBy = CardStackBy.bank;

  CardViewProvider() {
    _loadPreferences();
  }

  CardViewMode get viewMode => _viewMode;
  CardStackBy get stackBy => _stackBy;

  Future<void> _loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final savedMode = prefs.getString(_viewModeKey);
      if (savedMode != null) {
        _viewMode = savedMode == _legacyGroupedGridValue
            ? CardViewMode.stackedGrid
            : CardViewMode.values.firstWhere(
                (mode) => mode.name == savedMode,
                orElse: () => CardViewMode.carousel,
              );
      }

      final savedStackBy = prefs.getString(_stackByKey);
      if (savedStackBy != null) {
        _stackBy = CardStackBy.values.firstWhere(
          (axis) => axis.name == savedStackBy,
          orElse: () => CardStackBy.bank,
        );
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading card view preferences: $e');
    }
  }

  Future<void> setViewMode(CardViewMode mode) async {
    if (_viewMode == mode) return;
    _viewMode = mode;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_viewModeKey, mode.name);
    } catch (e) {
      debugPrint('Error saving card view mode: $e');
    }
  }

  Future<void> setStackBy(CardStackBy axis) async {
    if (_stackBy == axis) return;
    _stackBy = axis;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_stackByKey, axis.name);
    } catch (e) {
      debugPrint('Error saving card stack axis: $e');
    }
  }

  Future<void> cycleViewMode() {
    final next = CardViewMode
        .values[(_viewMode.index + 1) % CardViewMode.values.length];
    return setViewMode(next);
  }
}
