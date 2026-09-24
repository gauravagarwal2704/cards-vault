import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_nfc_kit/flutter_nfc_kit.dart';

import '../models/card_data.dart';
import '../services/nfc_service.dart';
import '../services/app_log_service.dart';

enum NfcState { idle, checking, scanning, success, error }

class NfcProvider extends ChangeNotifier with WidgetsBindingObserver {
  final NfcService _nfcService = NfcService();

  NfcState _state = NfcState.idle;
  CardData? _cardData;
  String? _errorMessage;
  NFCAvailability _availability = NFCAvailability.not_supported;
  Timer? _clearTimer;
  static const _dataTimeout = Duration(minutes: 5);

  NfcProvider() {
    WidgetsBinding.instance.addObserver(this);
  }

  NfcState get state => _state;
  CardData? get cardData => _cardData;
  String? get errorMessage => _errorMessage;

  NFCAvailability get availability => _availability;

  /// The hardware exists, whether or not the user has NFC switched on.
  bool get isNfcSupported => _availability != NFCAvailability.not_supported;

  /// Hardware exists and NFC is switched on, so a scan can start right away.
  bool get isNfcEnabled => _availability == NFCAvailability.available;

  Future<void> checkNfcAvailability() async {
    final span = AppLogService.instance.startSpan('NFC', 'Check availability');
    _state = NfcState.checking;
    notifyListeners();
    try {
      _availability = await _nfcService.getNfcAvailability();
      _state = NfcState.idle;
      span.complete(details: {'availability': _availability.name});
      notifyListeners();
    } catch (error, stackTrace) {
      _state = NfcState.error;
      _errorMessage = 'Could not check NFC availability.';
      span.fail(error, stackTrace);
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may have toggled NFC in system settings while we were backgrounded.
    if (state == AppLifecycleState.resumed) {
      _refreshAvailability();
    }
  }

  Future<void> _refreshAvailability() async {
    final availability = await _nfcService.getNfcAvailability();
    if (availability == _availability) return;
    _availability = availability;
    notifyListeners();
  }

  Future<void> readCard() async {
    final span = AppLogService.instance.startSpan('NFC', 'Read card');
    _state = NfcState.scanning;
    _errorMessage = null;
    _cardData = null;
    notifyListeners();

    try {
      CardData? card = await _nfcService.readCard();

      if (card != null) {
        _cardData = card;
        _state = NfcState.success;
        _errorMessage = null;

        _clearTimer?.cancel();
        _clearTimer = Timer(_dataTimeout, () {
          clearCardData();
        });
      } else {
        _state = NfcState.error;
        _errorMessage = 'Failed to read card data';
      }
      span.complete(details: {'success': card != null});
      notifyListeners();
    } on PlatformException catch (e, stackTrace) {
      span.fail(e, stackTrace);
      _state = NfcState.error;

      if (e.code == 'IOS_NOT_SUPPORTED') {
        _errorMessage =
            e.message ??
            'NFC Card reading not supported on iOS, please use Camera';
      } else if (e.code == '408') {
        _errorMessage = 'NFC session timeout. Please try again.';
      } else if (e.code == '200') {
        _errorMessage = 'NFC session cancelled by user.';
      } else if (e.code == '406') {
        _errorMessage = 'Card removed too early. Please hold the card steady.';
      } else {
        _errorMessage = 'NFC Error: ${e.message ?? e.code}';
      }

      notifyListeners();
    } catch (e, stackTrace) {
      span.fail(e, stackTrace);
      _state = NfcState.error;

      String errorString = e.toString().toLowerCase();

      if (errorString.contains('6985')) {
        _errorMessage = 'This card has NFC reading restrictions. Please use Camera Scan or Manual Entry instead.';
      } else if (errorString.contains('timeout')) {
        _errorMessage = 'NFC session timeout. Please try again.';
      } else if (errorString.contains('cancelled') ||
          errorString.contains('canceled')) {
        _errorMessage = 'NFC session cancelled.';
      } else if (errorString.contains('not available') ||
          errorString.contains('disabled')) {
        _errorMessage =
            'NFC is not available or disabled. Please enable NFC in settings.';
      } else if (errorString.contains('unsupported')) {
        _errorMessage = 'This card type is not supported.';
      } else if (errorString.contains('pan') ||
          errorString.contains('card number')) {
        _errorMessage = 'Could not read card number. Please try again.';
      } else if (errorString.contains('expiry')) {
        _errorMessage = 'Could not read expiry date. Please try again.';
      } else if (errorString.contains('aid') &&
          !errorString.contains('failed')) {
        _errorMessage =
            'Card not recognized. Please ensure it\'s a valid payment card.';
      } else if (errorString.contains('ppse')) {
        _errorMessage = 'Failed to communicate with card. Please try again.';
      } else {
        _errorMessage = 'Failed to read card. Please try again.';
      }

      notifyListeners();
    }
  }

  void reset() {
    _clearTimer?.cancel();
    _state = NfcState.idle;
    _cardData = null;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    if (_state == NfcState.error) {
      _state = NfcState.idle;
    }
    notifyListeners();
  }

  void clearCardData() {
    _clearTimer?.cancel();
    _cardData = null;
    _state = NfcState.idle;
    notifyListeners();
  }

  void setCardDataFromCamera(CardData cardData) {
    _cardData = cardData;
    _state = NfcState.success;
    _errorMessage = null;

    _clearTimer?.cancel();
    _clearTimer = Timer(_dataTimeout, () {
      clearCardData();
    });

    notifyListeners();
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
