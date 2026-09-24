import 'package:cards_wallet/models/app_icon_option.dart';
import 'package:cards_wallet/providers/app_icon_provider.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('app icon catalog persists a selected colorway', () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final provider = AppIconProvider();
      addTearDown(provider.dispose);
      while (!provider.isInitialized) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(AppIconCatalog.options, hasLength(7));
      expect(provider.selected.id, 'three_d');

      final error = await provider.selectIcon(AppIconCatalog.findById('red'));
      expect(error, isNull);
      expect(provider.selected.id, 'red');

      final preferences = await SharedPreferences.getInstance();
      expect(preferences.getString('appearance_app_icon'), 'red');

      final restored = AppIconProvider();
      addTearDown(restored.dispose);
      while (!restored.isInitialized) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(restored.selected.id, 'red');
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
