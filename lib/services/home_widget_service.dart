import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/banks.dart';
import '../models/card_data.dart';
import '../utils/card_network_utils.dart';
import 'secure_card_storage.dart';
import 'storage_path_guard.dart';
import 'widget_card_artwork.dart';

/// A launch request contains identifiers only, never card contents.
class WidgetLaunch {
  const WidgetLaunch({this.cardId, this.widgetId});
  final String? cardId;
  final int? widgetId;

  static WidgetLaunch? parse(Object? value) {
    if (value is! String) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.scheme != 'cardvault' ||
        uri.hasQuery ||
        uri.hasFragment ||
        uri.userInfo.isNotEmpty ||
        uri.hasPort ||
        uri.pathSegments.length != 1) {
      return null;
    }
    final id = uri.pathSegments.single;
    if (uri.host == 'cards') {
      try {
        requireSafeStorageIdentifier(id, label: 'card ID');
        return WidgetLaunch(cardId: id);
      } on FormatException {
        return null;
      }
    }
    if (uri.host == 'widgets' && RegExp(r'^[1-9][0-9]{0,9}$').hasMatch(id)) {
      final widgetId = int.tryParse(id);
      if (widgetId != null && widgetId <= 2147483647) {
        return WidgetLaunch(widgetId: widgetId);
      }
    }
    return null;
  }
}

/// Non-personal card appearance, without decrypting card contents.
Map<String, Object> widgetCardSnapshot(CardData card) {
  final bank = Banks.getById(card.bankId ?? '');
  return {
    'id': requireSafeStorageIdentifier(card.id!, label: 'card ID'),
    'bank': bank?.shortName ?? 'CardVault',
    'lastFour': RegExp(r'^[0-9]{4}$').hasMatch(card.lastFourDigits)
        ? card.lastFourDigits
        : '',
    'network': CardNetworkUtils.getNetworkName(
      CardNetworkUtils.networkFromCardType(card.cardType),
    ),
    'category': card.cardCategory == CardCategory.debit ? 'Debit' : 'Credit',
    'color': bank?.primaryColor.toARGB32() ?? 0xFF344D8C,
  };
}

/// Names cannot carry accidentally pasted card numbers, control characters or
/// bidirectional overrides into the launcher. Unicode letters remain supported.
String widgetDisplayName(String? value) => String.fromCharCodes(
  (value ?? '')
      .replaceAll(RegExp(r"[^\p{L}\p{M} .’'-]", unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .runes
      .take(48),
);

/// Keep ordinary nickname digits, but discard pasted card numbers and controls.
String widgetDisplayNickname(String? value) => String.fromCharCodes(
  (value ?? '')
      .replaceAll(RegExp(r'(?<!\d)(?:\d[ -]?){12,19}(?!\d)'), '')
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N} .’\x27&-]', unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .runes
      .take(48),
);

/// Call only for IDs selected in an active widget.
/// No card number, expiry, CVV, notes or photos are decrypted or copied here.
Future<Map<String, Object>> widgetCardPreview(
  CardData card, {
  required String fallbackName,
}) async {
  String name;
  try {
    name = widgetDisplayName(await card.getDecryptedCardholderName());
  } catch (_) {
    // An unreadable encrypted name must never block or expose other fields.
    name = '';
  }
  return {
    ...widgetCardSnapshot(card),
    'holder': name.isEmpty ? widgetDisplayName(fallbackName) : name,
    'nickname': widgetDisplayNickname(card.cardNickname),
  };
}

class HomeWidgetService {
  HomeWidgetService._();
  static final instance = HomeWidgetService._();
  static const channel = MethodChannel('cards_wallet/home_widgets');
  final pending = ValueNotifier<WidgetLaunch?>(null);
  bool _started = false;
  Color _fallbackPrimary = const Color(0xFF6750A4);
  Color _fallbackSecondary = const Color(0xFFEADDFF);

  void updateTheme(
    Color primary,
    Color secondary, {
    bool refreshWidgets = false,
  }) {
    if (_fallbackPrimary == primary && _fallbackSecondary == secondary) return;
    _fallbackPrimary = primary;
    _fallbackSecondary = secondary;
    if (_started && refreshWidgets) refresh();
  }

  Future<void> _syncTail = Future<void>.value();
  int _refreshGeneration = 0;

  Future<void> start() async {
    if (!Platform.isAndroid || _started) return;
    _started = true;
    channel.setMethodCallHandler((call) async {
      if (call.method == 'launch') {
        final launch = WidgetLaunch.parse(
          await channel.invokeMethod<String>('takeLaunch'),
        );
        if (launch != null) pending.value = launch;
      }
    });
    SecureCardStorage.changes.addListener(refresh);
    try {
      final launch = WidgetLaunch.parse(
        await channel.invokeMethod<String>('takeLaunch'),
      );
      if (launch != null && pending.value == null) pending.value = launch;
    } on PlatformException {
      /* A normal app launch remains usable. */
    } on MissingPluginException {
      /* Other platforms do not have widgets. */
    }
  }

  void refresh() {
    if (!Platform.isAndroid) return;
    final generation = ++_refreshGeneration;
    _syncTail = _syncTail.then((_) async {
      if (generation != _refreshGeneration) return;
      try {
        // Avoid a second secure-storage read for users without home widgets.
        if (await channel.invokeMethod<bool>('hasWidgets') != true) return;
        final cards = await SecureCardStorage().loadCards();
        final selected =
            (await channel.invokeListMethod<String>('previewCardIds') ?? [])
                .toSet();
        final preferences = await SharedPreferences.getInstance();
        final fallbackName =
            preferences.getString('profile_display_name') ?? '';
        final snapshots = <Map<String, Object>>[];
        for (final card in cards.where((card) => card.id != null)) {
          if (generation != _refreshGeneration) return;
          if (selected.contains(card.id)) {
            final preview = await widgetCardPreview(
              card,
              fallbackName: fallbackName,
            );
            try {
              preview.addAll(
                await WidgetCardArtwork.render(
                  card,
                  fallbackPrimary: _fallbackPrimary,
                  fallbackSecondary: _fallbackSecondary,
                  includeCustomImage: true,
                ),
              );
            } catch (_) {
              // Keep safe textual details usable if an artwork asset is unreadable.
            }
            snapshots.add(preview);
          } else {
            snapshots.add({
              'id': requireSafeStorageIdentifier(card.id!, label: 'card ID'),
            });
          }
        }
        if (generation != _refreshGeneration) return;
        await channel.invokeMethod<void>('sync', snapshots);
      } catch (_) {
        if (generation != _refreshGeneration) return;
        // Fail closed: discard previews rather than leave stale card metadata.
        try {
          await channel.invokeMethod<void>('clearPreviews');
        } catch (_) {}
      }
    });
  }

  Future<Map<Object?, Object?>> configuration(int widgetId) async =>
      await channel.invokeMapMethod<Object?, Object?>(
        'configuration',
        widgetId,
      ) ??
      {};

  Future<void> save(int widgetId, List<String> ids) async {
    await channel.invokeMethod<void>('save', {
      'widgetId': widgetId,
      'ids': ids,
    });
    refresh();
    await _syncTail;
  }
}
