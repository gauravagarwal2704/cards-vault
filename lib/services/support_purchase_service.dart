import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_log_service.dart';

/// The store-facing contract used by the supporter screen.
///
/// Keeping this small makes the UI testable without opening a real Google Play
/// purchase sheet.
abstract interface class SupportPurchaseController implements Listenable {
  bool get isLoading;
  bool get isAvailable;
  bool get isPurchasing;
  String? get message;
  List<ProductDetails> get products;
  int get purchaseSuccessSerial;
  String? get lastPurchasedPrice;
  int get supporterStars;

  Future<void> initialize({bool forceRefresh = false});
  Future<bool> purchase(ProductDetails product);
}

/// Handles optional, repeatable supporter tips through Google Play Billing.
///
/// Tips do not grant an entitlement. The products must therefore be configured
/// as consumable one-time products in Play Console so a supporter can tip more
/// than once.
class SupportPurchaseService extends ChangeNotifier
    implements SupportPurchaseController {
  SupportPurchaseService._({InAppPurchase? billing})
    : _billing = billing ?? InAppPurchase.instance;

  @visibleForTesting
  SupportPurchaseService.forTesting({required InAppPurchase billing})
    : this._(billing: billing);

  static final SupportPurchaseService instance = SupportPurchaseService._();

  /// Create these IDs as consumable one-time products in Play Console.
  /// Their localized prices, rather than hard-coded currency values, are shown
  /// to the user.
  static const Set<String> productIds = {
    'support_tip_1',
    'support_tip_2',
    'support_tip_3',
    'support_tip_4',
    'support_tip_5',
    'support_tip_6',
    'support_tip_7',
  };
  static const String _supporterStarsKey = 'supporter_stars';

  final InAppPurchase _billing;
  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Future<void>? _initialization;
  Future<void>? _listenerInitialization;
  bool _started = false;
  bool _isLoading = false;
  bool _isAvailable = false;
  bool _isPurchasing = false;
  String? _message;
  List<ProductDetails> _products = const [];
  int _purchaseSuccessSerial = 0;
  String? _lastPurchasedPrice;
  int _supporterStars = 0;
  bool _supporterStarsLoaded = false;

  bool get _isGooglePlayPlatform =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get isAvailable => _isAvailable;

  @override
  bool get isPurchasing => _isPurchasing;

  @override
  String? get message => _message;

  @override
  List<ProductDetails> get products => List.unmodifiable(_products);

  @override
  int get purchaseSuccessSerial => _purchaseSuccessSerial;

  @override
  String? get lastPurchasedPrice => _lastPurchasedPrice;

  @override
  int get supporterStars => _supporterStars;

  @override
  Future<void> initialize({bool forceRefresh = false}) {
    if (_initialization != null) return _initialization!;
    if (_started && !forceRefresh) return Future<void>.value();

    final future = _loadProducts();
    _initialization = future;
    return future.whenComplete(() => _initialization = null);
  }

  Future<void> _loadProducts() async {
    _started = true;
    _isLoading = true;
    _message = null;
    notifyListeners();

    await _ensureSupporterStarsLoaded();

    if (!_isGooglePlayPlatform) {
      _isAvailable = false;
      _isLoading = false;
      _message =
          'Supporter tips are available in the Android app from Google Play.';
      notifyListeners();
      return;
    }

    await startListening();

    try {
      _isAvailable = await _billing.isAvailable();
      if (!_isAvailable) {
        _message = 'Google Play Billing is unavailable. Install CardVault from Google Play and try again.';
        return;
      }

      final response = await _billing.queryProductDetails(productIds);
      if (response.error != null) {
        _message = response.error!.message;
      }

      _products = [...response.productDetails]
        ..sort((left, right) => left.rawPrice.compareTo(right.rawPrice));

      if (_products.isEmpty && _message == null) {
        _message = 'Tip options are not available yet. Check the one-time product setup in Play Console.';
      }

      AppLogService.instance.action(
        'Support',
        'Google Play tip products loaded',
        details: {
          'availableProducts': _products.length,
          'missingProducts': response.notFoundIDs.length,
        },
      );
    } catch (error, stackTrace) {
      _isAvailable = false;
      _message = 'Could not connect to Google Play. Please try again.';
      AppLogService.instance.recordFailure(
        'Load supporter tip products',
        error,
        stackTrace,
        category: 'Failure/Billing',
      );
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Starts only the purchase update listener. This runs at app startup so a
  /// delayed purchase can be completed, while catalog/network work remains
  /// lazy until the supporter page is opened.
  Future<void> startListening() {
    if (!_isGooglePlayPlatform || _purchaseSubscription != null) {
      return Future<void>.value();
    }
    if (_listenerInitialization != null) return _listenerInitialization!;

    final future = _startListening();
    _listenerInitialization = future;
    return future.whenComplete(() => _listenerInitialization = null);
  }

  Future<void> _startListening() async {
    await _ensureSupporterStarsLoaded();
    _purchaseSubscription = _billing.purchaseStream.listen(
      _handlePurchaseUpdates,
      onError: _handlePurchaseStreamError,
    );
  }

  Future<void> _ensureSupporterStarsLoaded() async {
    if (_supporterStarsLoaded) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _supporterStars = preferences.getInt(_supporterStarsKey) ?? 0;
    } catch (error, stackTrace) {
      AppLogService.instance.recordFailure(
        'Load supporter stars',
        error,
        stackTrace,
        category: 'Failure/Billing',
      );
    } finally {
      _supporterStarsLoaded = true;
    }
  }

  @override
  Future<bool> purchase(ProductDetails product) async {
    if (_isPurchasing || !_products.any((item) => item.id == product.id)) {
      return false;
    }

    _isPurchasing = true;
    _message = null;
    notifyListeners();

    AppLogService.instance.action(
      'Support',
      'Google Play tip checkout requested',
      details: {'product': product.id},
    );

    try {
      final launched = await _billing.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: product),
        autoConsume: true,
      );
      if (!launched) {
        _isPurchasing = false;
        _message = 'Google Play could not start checkout. Please try again.';
        notifyListeners();
      }
      return launched;
    } catch (error, stackTrace) {
      _isPurchasing = false;
      _message = 'Google Play could not start checkout. Please try again.';
      notifyListeners();
      AppLogService.instance.recordFailure(
        'Start supporter tip checkout',
        error,
        stackTrace,
        category: 'Failure/Billing',
      );
      return false;
    }
  }

  Future<void> _handlePurchaseUpdates(List<PurchaseDetails> purchases) async {
    var refreshProducts = false;
    for (final purchase in purchases) {
      // Play can dismiss checkout without a Purchase object. The plugin emits
      // a cancellation/error with an empty product ID in that case.
      final checkoutEndedWithoutProduct =
          purchase.productID.isEmpty &&
          _isPurchasing &&
          (purchase.status == PurchaseStatus.canceled ||
              purchase.status == PurchaseStatus.error);
      if (!productIds.contains(purchase.productID) &&
          !checkoutEndedWithoutProduct) {
        continue;
      }

      if (purchase.status == PurchaseStatus.pending) {
        _isPurchasing = true;
        continue;
      }
      if (purchase.status == PurchaseStatus.error) {
        _isPurchasing = false;
        _message =
            purchase.error?.message ??
            'The Google Play payment did not complete.';
        continue;
      }
      if (purchase.status == PurchaseStatus.canceled) {
        _isPurchasing = false;
        _message = null;
        refreshProducts = true;
        continue;
      }

      try {
        if (purchase.pendingCompletePurchase) {
          await _billing.completePurchase(purchase);
        }
        _isPurchasing = false;
        _message = null;
        if (purchase.status == PurchaseStatus.purchased) {
          ProductDetails? matchingProduct;
          for (final product in _products) {
            if (product.id == purchase.productID) {
              matchingProduct = product;
              break;
            }
          }
          _lastPurchasedPrice = matchingProduct?.price;
          await _addSupporterStar();
          _purchaseSuccessSerial += 1;
          AppLogService.instance.action(
            'Support',
            'Google Play tip completed',
            details: {'product': purchase.productID},
          );
        }
      } catch (error, stackTrace) {
        _isPurchasing = false;
        _message = 'Your payment was received, but Google Play could not finish it. Please try again later.';
        AppLogService.instance.recordFailure(
          'Complete supporter tip purchase',
          error,
          stackTrace,
          category: 'Failure/Billing',
        );
      }
    }
    notifyListeners();
    if (refreshProducts) {
      await initialize(forceRefresh: true);
    }
  }

  @override
  void dispose() {
    unawaited(_purchaseSubscription?.cancel());
    super.dispose();
  }

  Future<void> _addSupporterStar() async {
    _supporterStars += 1;
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setInt(_supporterStarsKey, _supporterStars);
    } catch (error, stackTrace) {
      AppLogService.instance.recordFailure(
        'Save supporter star',
        error,
        stackTrace,
        category: 'Failure/Billing',
      );
    }
  }

  void _handlePurchaseStreamError(Object error, StackTrace stackTrace) {
    _isPurchasing = false;
    _message = 'Could not read the Google Play payment status.';
    notifyListeners();
    AppLogService.instance.recordFailure(
      'Read supporter tip purchase status',
      error,
      stackTrace,
      category: 'Failure/Billing',
    );
  }
}
