import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/services/home_widget_service.dart';
import 'package:flutter_test/flutter_test.dart';

class _NameCard extends CardData {
  _NameCard(this.holder)
    : super(
        id: 'named',
        encryptedCardNumber: 'secret-number',
        encryptedExpiryDate: 'secret-expiry',
        lastFourDigits: '4242',
        cardType: 'Visa',
      );
  final String? holder;
  @override
  Future<String?> getDecryptedCardholderName() async => holder;
  @override
  Future<String> getDecryptedCardNumber() =>
      throw StateError('Must not decrypt full number');
  @override
  Future<String> getDecryptedExpiryDate() =>
      throw StateError('Must not decrypt expiry');
}

void main() {
  test(
    'widget launches accept only bounded identifiers and known destinations',
    () {
      expect(
        WidgetLaunch.parse('cardvault://cards/abc-123')?.cardId,
        'abc-123',
      );
      expect(WidgetLaunch.parse('cardvault://widgets/42')?.widgetId, 42);
      for (final link in [
        null,
        123,
        '',
        'https://cards/abc',
        'cardvault://cards',
        'cardvault://cards/groups',
        'cardvault://cards/..',
        'cardvault://cards/a/b',
        'cardvault://cards/a?edit=true',
        'cardvault://cards/a#secret',
        'cardvault://cards/%2Fetc',
        'cardvault://cards:80/a',
        'cardvault://user@cards/a',
        'cardvault://widgets/0',
        'cardvault://widgets/-1',
        'cardvault://widgets/2147483648',
        'cardvault://edit/a',
        'cardvault://cards/${'a' * 129}',
      ]) {
        expect(WidgetLaunch.parse(link), isNull, reason: '$link');
      }
    },
  );

  test('appearance snapshot excludes secrets, user text and card images', () {
    final card = CardData(
      id: 'card-1',
      encryptedCardNumber: 'secret-number',
      encryptedExpiryDate: 'secret-expiry',
      encryptedCvv: 'secret-cvv',
      encryptedCardholderName: 'secret-name',
      lastFourDigits: '4242',
      cardType: 'untrusted-network',
      bankId: 'hdfc',
      cardNickname: 'untrusted nickname with card data',
      notes: 'secret-notes',
      customBackgroundImagePath: '/private/card-photo.png',
      attachmentIds: ['secret-attachment'],
    );
    expect(widgetCardSnapshot(card), {
      'id': 'card-1',
      'bank': 'HDFC',
      'lastFour': '4242',
      'network': 'Unknown',
      'category': 'Credit',
      'color': 0xFF004C8F,
    });
    expect(
      widgetCardSnapshot(
        card.copyWith(lastFourDigits: '1234567812345678'),
      )['lastFour'],
      '',
    );
    expect(
      widgetCardSnapshot(card.copyWith(bankId: 'injected bank name'))['bank'],
      'CardVault',
    );
  });
  test('selected preview includes only safe labels and known type', () async {
    final preview = await widgetCardPreview(
      _NameCard('Avery Sharma'),
      fallbackName: 'Profile Name',
    );
    expect(preview['holder'], 'Avery Sharma');
    expect(preview['network'], 'Visa');
    expect(preview['category'], 'Credit');
    expect(preview.keys.toSet(), {
      'id',
      'bank',
      'lastFour',
      'network',
      'category',
      'color',
      'holder',
      'nickname',
    });
    expect(
      (await widgetCardPreview(
        _NameCard(null),
        fallbackName: 'Profile Name',
      ))['holder'],
      'Profile Name',
    );
  });

  test(
    'launcher names remove numbers and controls and preserve Unicode names',
    () {
      expect(
        widgetDisplayName('Avery 4111 1111 1111 1111\nSharma'),
        'Avery Sharma',
      );
      expect(widgetDisplayName('José O’Connor'), 'José O’Connor');
      expect(widgetDisplayName('आरव शर्मा'), 'आरव शर्मा');
      expect(widgetDisplayName('Avery\u202e1234'), 'Avery');
      expect(widgetDisplayName('A' * 100).runes.length, 48);
      expect(widgetDisplayNickname('Fuel 1'), 'Fuel 1');
      expect(widgetDisplayNickname('Travel 4111 1111 1111 1111'), 'Travel');
      expect(widgetDisplayNickname('Home\u202e'), 'Home');
    },
  );
}
