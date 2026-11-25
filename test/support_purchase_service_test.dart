import 'dart:async';

import 'package:cards_wallet/services/support_purchase_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeBilling implements InAppPurchase {
  final updates = StreamController<List<PurchaseDetails>>.broadcast();
  final product = ProductDetails(
    id: 'support_tip_1',
    title: 'Supporter Star',
    description: 'One cosmetic star',
    price: '₹29',
    rawPrice: 29,
    currencyCode: 'INR',
  );
  int queries = 0;
  int checkouts = 0;
  int completions = 0;

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => updates.stream;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ProductDetailsResponse> queryProductDetails(Set<String> ids) async {
    queries++;
    return ProductDetailsResponse(productDetails: [product], notFoundIDs: []);
  }

  @override
  Future<bool> buyConsumable({
    required PurchaseParam purchaseParam,
    bool autoConsume = true,
  }) async {
    checkouts++;
    return true;
  }

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completions++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PurchaseDetails _update(PurchaseStatus status, {String productID = ''}) =>
    PurchaseDetails(
      productID: productID,
      verificationData: PurchaseVerificationData(
        localVerificationData: '',
        serverVerificationData: '',
        source: 'google_play',
      ),
      transactionDate: null,
      status: status,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _FakeBilling billing;
  late SupportPurchaseService service;

  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    billing = _FakeBilling();
    service = SupportPurchaseService.forTesting(billing: billing);
    await service.initialize();
  });

  tearDown(() async {
    service.dispose();
    await billing.updates.close();
    debugDefaultTargetPlatformOverride = null;
  });

  for (final productID in ['', 'support_tip_1']) {
    test(
      'cancellation ($productID) refreshes prices and allows retry',
      () async {
        await service.purchase(billing.product);
        expect(service.isPurchasing, isTrue);

        billing.updates.add([
          _update(PurchaseStatus.canceled, productID: productID),
        ]);
        await Future<void>.delayed(Duration.zero);

        expect(service.isPurchasing, isFalse);
        expect(service.isLoading, isFalse);
        expect(service.message, isNull);
        expect(service.supporterStars, 0);
        expect(service.purchaseSuccessSerial, 0);
        expect(billing.completions, 0);
        expect(billing.queries, 2);
        expect(await service.purchase(billing.product), isTrue);
        expect(billing.checkouts, 2);
      },
    );
  }

  test('unidentified checkout error clears waiting and allows retry', () async {
    await service.purchase(billing.product);
    billing.updates.add([
      _update(PurchaseStatus.error)
        ..error = IAPError(
          source: 'google_play',
          code: 'error',
          message: 'Failed',
        ),
    ]);
    await Future<void>.delayed(Duration.zero);

    expect(service.isPurchasing, isFalse);
    expect(service.message, 'Failed');
    expect(service.supporterStars, 0);
    expect(await service.purchase(billing.product), isTrue);
  });

  test(
    'pending and unrelated updates do not release active checkout',
    () async {
      await service.purchase(billing.product);
      billing.updates.add([
        _update(PurchaseStatus.pending, productID: 'support_tip_1'),
        _update(PurchaseStatus.canceled, productID: 'unrelated_product'),
        _update(PurchaseStatus.purchased),
      ]);
      await Future<void>.delayed(Duration.zero);

      expect(service.isPurchasing, isTrue);
      expect(service.supporterStars, 0);
      expect(await service.purchase(billing.product), isFalse);
      expect(billing.queries, 1);
    },
  );
}
