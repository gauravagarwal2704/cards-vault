import 'package:cards_wallet/providers/app_icon_provider.dart';
import 'package:cards_wallet/screens/support_developer_screen.dart';
import 'package:cards_wallet/services/support_purchase_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSupportPurchaseController extends ChangeNotifier
    implements SupportPurchaseController {
  _FakeSupportPurchaseController()
    : products = [
        _product('support_tip_1', 29),
        _product('support_tip_2', 49),
        _product('support_tip_3', 99),
        _product('support_tip_4', 149),
        _product('support_tip_5', 249),
        _product('support_tip_6', 499),
        _product('support_tip_7', 999),
      ];

  static ProductDetails _product(String id, double amount) => ProductDetails(
    id: id,
    title: 'CardVault supporter tip',
    description: 'Adds one cosmetic Supporter Star',
    price: '₹${amount.toStringAsFixed(0)}',
    rawPrice: amount,
    currencyCode: 'INR',
    currencySymbol: '₹',
  );

  @override
  bool isAvailable = true;

  @override
  bool isLoading = false;

  @override
  bool isPurchasing = false;

  @override
  String? lastPurchasedPrice;

  @override
  String? message;

  @override
  final List<ProductDetails> products;

  @override
  int purchaseSuccessSerial = 0;

  @override
  int supporterStars = 0;

  ProductDetails? purchasedProduct;

  @override
  Future<void> initialize({bool forceRefresh = false}) async {}

  @override
  Future<bool> purchase(ProductDetails product) async {
    purchasedProduct = product;
    lastPurchasedPrice = product.price;
    supporterStars += 1;
    purchaseSuccessSerial += 1;
    notifyListeners();
    return true;
  }
}

void main() {
  testWidgets('support page offers quick tips and all seven selectable amounts', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({});
    final controller = _FakeSupportPurchaseController();

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AppIconProvider(),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: SupportDeveloperScreen(controller: controller),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('close-support-developer')),
      findsOneWidget,
    );
    expect(find.text('CardVault'), findsOneWidget);
    expect(find.text('Support independent development'), findsOneWidget);
    expect(
      find.text('Help fund future feature enhancements for everyone'),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('tip-support_tip_1')), findsOneWidget);
    expect(find.byKey(const ValueKey('tip-support_tip_3')), findsOneWidget);
    expect(find.byKey(const ValueKey('tip-support_tip_5')), findsOneWidget);
    expect(find.text('Support with Google Play'), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('buy-me-a-coffee-link')),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('buy-me-a-coffee-link')), findsOneWidget);
    expect(find.byKey(const ValueKey('buy-me-a-chai-link')), findsOneWidget);
    expect(find.byKey(const ValueKey('buy-me-a-chai-icon')), findsOneWidget);
    expect(find.text('Buy me a Chai'), findsOneWidget);
    final chaiButton = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(const ValueKey('buy-me-a-chai-link')),
        matching: find.byType(FilledButton),
      ),
    );
    final chaiShape = chaiButton.style?.shape?.resolve({});
    expect(chaiShape, isA<RoundedRectangleBorder>());
    expect(
      (chaiShape! as RoundedRectangleBorder).borderRadius,
      BorderRadius.circular(10),
    );
    final chaiText = find.text('Buy me a Chai');
    final chaiParagraph = tester.renderObject<RenderParagraph>(chaiText);
    expect(
      chaiParagraph.didExceedMaxLines,
      isFalse,
      reason:
          'Button ${tester.getSize(find.byKey(const ValueKey('buy-me-a-chai-link')))}; '
          'text ${tester.getSize(chaiText)}',
    );
    expect(
      find.byKey(const ValueKey('buy-me-a-coffee-brand-artwork')),
      findsOneWidget,
    );
    expect(find.text('Other ways to support'), findsOneWidget);
    expect(
      tester.getCenter(find.byKey(const ValueKey('buy-me-a-coffee-link'))).dy,
      closeTo(
        tester.getCenter(find.byKey(const ValueKey('buy-me-a-chai-link'))).dy,
        0.1,
      ),
    );

    await tester.ensureVisible(find.byKey(const ValueKey('more-amounts')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('more-amounts')));
    await tester.pumpAndSettle();
    expect(find.text('More amounts'), findsNWidgets(2));
    expect(find.byType(TextField), findsNothing);
    for (var tier = 1; tier <= 7; tier++) {
      expect(
        find.byKey(ValueKey('more-amounts-support_tip_$tier')),
        findsOneWidget,
      );
    }

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('submit-more-amounts')),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.byKey(const ValueKey('more-amounts-support_tip_7')));
    await tester.pump();
    expect(
      tester
          .widget<ChoiceChip>(
            find.byKey(const ValueKey('more-amounts-support_tip_7')),
          )
          .selected,
      isTrue,
    );
    await tester.pump();
    expect(find.text('Purchase for ₹999'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('submit-more-amounts')));
    await tester.pumpAndSettle();

    expect(controller.purchasedProduct?.id, 'support_tip_7');
    expect(find.text('1 Supporter Star'), findsOneWidget);
    expect(
      find.text(
        'Thank you for your ₹999 support! You earned a Supporter Star.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
