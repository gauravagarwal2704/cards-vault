import 'dart:io';
import 'dart:typed_data';

import 'package:cards_wallet/data/banks.dart';
import 'package:cards_wallet/data/card_designs.dart';
import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/services/widget_card_artwork.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

CardData _card(
  String network, {
  String? design,
  int? start,
  int? end,
  String? path,
}) => CardData(
  id: 'artwork-test',
  encryptedCardNumber: 'never-export',
  encryptedExpiryDate: 'never-export',
  encryptedCvv: 'never-export',
  lastFourDigits: '4242',
  cardType: network,
  bankId: 'hdfc',
  designId: design,
  customGradientStartColor: start,
  customGradientEndColor: end,
  customGradientAngle: 63,
  customBackgroundImagePath: path,
);

void main() {
  testWidgets(
    'widget artwork uses saved design assets and actual cropped network logos',
    (tester) async {
      final fixtures = [
        _card('Visa', design: CardDesigns.gradient.first.id),
        _card('Mastercard', design: CardDesigns.dualTone.first.id),
        _card('RuPay', design: CardDesigns.abstract.first.id),
        _card('American Express', design: CardDesigns.monochrome.first.id),
      ];
      final output = <Map<String, Object>>[];
      for (var i = 0; i < fixtures.length; i++) {
        final result = await tester.runAsync(
          () => WidgetCardArtwork.render(
            fixtures[i],
            fallbackPrimary: Banks.all.first.primaryColor,
            fallbackSecondary: Banks.all.first.secondaryColor,
          ),
        );
        expect(result, isNotNull);
        final artwork = result!;
        final background = img.decodeJpg(artwork['background'] as Uint8List);
        final logo = img.decodePng(artwork['logo'] as Uint8List);
        final bankLogo = img.decodePng(artwork['bankLogo'] as Uint8List);
        expect(background?.width, WidgetCardArtwork.width);
        expect(background?.height, WidgetCardArtwork.height);
        expect(logo, isNotNull);
        expect(bankLogo, isNotNull);
        expect((artwork['background'] as Uint8List).length, lessThan(131072));
        expect(artwork.keys.toSet(), {
          'background',
          'foreground',
          'logo',
          'bankLogo',
          'customArtwork',
        });
        expect(artwork['customArtwork'], false);
        if (const bool.fromEnvironment('WRITE_WIDGET_PREVIEWS')) {
          await tester.runAsync(() async {
            final dir = Directory('build/widget-previews');
            await dir.create(recursive: true);
            await File('${dir.path}/foreground-$i.txt')
                .writeAsString('${artwork['foreground']}');
            await File('${dir.path}/artwork-$i.jpg')
                .writeAsBytes(artwork['background'] as Uint8List);
            await File('${dir.path}/logo-$i.png')
                .writeAsBytes(artwork['logo'] as Uint8List);
            await File('${dir.path}/bank-logo-$i.png')
                .writeAsBytes(artwork['bankLogo'] as Uint8List);
          });
        }
        output.add(artwork);
      }
      expect(output[0]['background'], isNot(equals(output[1]['background'])));
      final changedFields = await tester.runAsync(
        () => WidgetCardArtwork.render(
          fixtures.first.copyWith(
            lastFourDigits: '9999',
            cardNickname: 'DO NOT EXPORT',
            notes: 'DO NOT EXPORT',
          ),
          fallbackPrimary: Banks.all.first.primaryColor,
          fallbackSecondary: Banks.all.first.secondaryColor,
        ),
      );
      expect(
        changedFields!['background'],
        orderedEquals(output[0]['background'] as Uint8List),
        reason: 'Background rendering must not capture card numbers, names, notes or other wallet overlays.',
      );
    },
  );

  testWidgets(
    'custom gradients work without bank substitution or external image access',
    (tester) async {
      final result = await tester.runAsync(
        () => WidgetCardArtwork.render(
          _card(
            'Visa',
            start: 0xFF251247,
            end: 0xFF81D8DB,
            path: '/outside/private-card-photo.png',
          ),
          fallbackPrimary: Colors.red,
          fallbackSecondary: Colors.orange,
          includeCustomImage: true,
        ),
      );
      expect(result!['customArtwork'], false);
      expect(img.decodeJpg(result['background'] as Uint8List), isNotNull);
      expect(result.keys, isNot(contains('customBackgroundImagePath')));
    },
  );

  testWidgets('bank without a real logo falls back to its name', (tester) async {
    final result = await tester.runAsync(
      () => WidgetCardArtwork.render(
        _card('Visa').copyWith(bankId: 'karurvysya'),
        fallbackPrimary: Colors.blue,
        fallbackSecondary: Colors.indigo,
      ),
    );
    expect(result, isNot(contains('bankLogo')));
  });
}
