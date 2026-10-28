import 'dart:io';
import 'dart:ui' as ui;

import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/models/card_image_placement.dart';
import 'package:cards_wallet/widgets/card_background_surface.dart';
import 'package:cards_wallet/widgets/card_image_alignment_editor.dart';
import 'package:cards_wallet/widgets/wallet_card.dart';
import 'package:cards_wallet/widgets/wallet_card_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  test('image placement fills the card at all allowed crop positions', () {
    for (final image in const [
      Size(1200, 400),
      Size(400, 1200),
      Size(600, 400),
    ]) {
      for (final viewport in const [Size(350, 220), Size(120, 76)]) {
        for (final zoom in [1.0, 2.5, 4.0]) {
          for (final offset in [-1.0, 0.0, 1.0]) {
            final rect = CardImagePlacement(
              zoom: zoom,
              x: offset,
              y: offset,
            ).imageRect(image, viewport);
            expect(rect.left, lessThanOrEqualTo(0));
            expect(rect.top, lessThanOrEqualTo(0));
            expect(rect.right, greaterThanOrEqualTo(viewport.width - 0.001));
            expect(rect.bottom, greaterThanOrEqualTo(viewport.height - 0.001));
          }
        }
      }
    }
  });

  test('placement survives save and copy; legacy cards remain centered', () {
    final card = CardData(
      encryptedCardNumber: 'encrypted',
      encryptedExpiryDate: 'encrypted',
      lastFourDigits: '1111',
      cardType: 'Visa',
      customBackgroundImagePath: '/background.jpg',
      backgroundImagePlacement: const CardImagePlacement(
        zoom: 2.5,
        x: .8,
        y: -.4,
      ),
    );
    final restored = CardData.fromJson(card.toJson())
        .copyWith(cardNickname: 'Updated');
    expect(
      restored.backgroundImagePlacement.toJson(),
      card.backgroundImagePlacement.toJson(),
    );
    expect(
      restored
          .copyWith(clearCustomBackgroundImage: true)
          .backgroundImagePlacement
          .zoom,
      1,
    );
    final legacy = card.toJson()..remove('backgroundImagePlacement');
    expect(
      CardData.fromJson(legacy).backgroundImagePlacement.toJson(),
      const CardImagePlacement().toJson(),
    );
    expect(
      CardImagePlacement.fromJson({'zoom': double.nan, 'x': 20, 'y': -20})
          .toJson(),
      {'zoom': 1.0, 'x': 1.0, 'y': -1.0},
    );
  });

  testWidgets(
    'alignment supports zoom, dragging, pinch, and reset with card number visible',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      final directory = Directory.systemTemp.createTempSync(
        'card-image-alignment-',
      );
      addTearDown(() => directory.deleteSync(recursive: true));
      final file = File('${directory.path}/background.png');
      final image = image_lib.Image(width: 600, height: 400);
      for (final pixel in image) {
        pixel.setRgb(220, 40 + pixel.y ~/ 4, 60 + pixel.x ~/ 4);
      }
      file.writeAsBytesSync(image_lib.encodePng(image));
      await tester.pumpWidget(const MaterialApp(home: Scaffold()));
      await tester.runAsync(() async {
        final context = tester.element(find.byType(Scaffold));
        await precacheImage(FileImage(file), context);
        await precacheImage(ResizeImage(FileImage(file), width: 512), context);
      });
      var placement = const CardImagePlacement();
      final boundaryKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 350,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    return RepaintBoundary(
                      key: boundaryKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CardImageAlignmentPreview(
                            path: file.path,
                            placement: placement,
                            onChanged: (next) =>
                                setState(() => placement = next),
                            child: AspectRatio(
                              aspectRatio: 1.586,
                              child: CardBackgroundSurface(
                                customBackgroundImagePath: file.path,
                                backgroundImagePlacement: placement,
                                fallbackPrimaryColor: Colors.green,
                                fallbackSecondaryColor: Colors.blue,
                                borderRadius: BorderRadius.circular(20),
                                child: const WalletCardFace(
                                  bank: null,
                                  network: CardNetwork.visa,
                                  categoryName: 'Credit',
                                  nickname: 'My card',
                                  cardNumber: '4111 1111 1111 1111',
                                  cardholderName: 'Test User',
                                  expiryDate: '12/30',
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ),
                          ),
                          CardImageAlignmentEditor(
                            placement: placement,
                            onChanged: (next) =>
                                setState(() => placement = next),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('4111 1111 1111 1111'), findsOneWidget);

      final slider = find.byKey(const ValueKey('card-image-zoom'));
      await tester.drag(slider, const Offset(45, 0));
      await tester.pumpAndSettle();
      expect(placement.zoom, greaterThan(1));
      final preview = find.byKey(
        const ValueKey('card-image-alignment-preview'),
      );
      await tester.drag(preview, const Offset(60, -30));
      await tester.pumpAndSettle();
      expect(placement.x, lessThan(0));
      expect(placement.y, greaterThan(0));
      expect(find.text('4111 1111 1111 1111'), findsOneWidget);

      final previousZoom = placement.zoom;
      final center = tester.getCenter(preview);
      final first = await tester.startGesture(
        center - const Offset(30, 0),
        pointer: 1,
      );
      final second = await tester.startGesture(
        center + const Offset(30, 0),
        pointer: 2,
      );
      await first.moveTo(center - const Offset(45, 0));
      await second.moveTo(center + const Offset(45, 0));
      await first.up();
      await second.up();
      await tester.pumpAndSettle();
      expect(placement.zoom, greaterThanOrEqualTo(previousZoom));

      final surface = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(CardBackgroundSurface),
              matching: find.byType(Container),
            )
            .first,
      );
      final shadow = (surface.decoration! as BoxDecoration).boxShadow!.single;
      expect(shadow.color.r, shadow.color.g);
      expect(shadow.color.g, shadow.color.b);
      await tester.runAsync(() async {
        final boundary =
            boundaryKey.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final screenshot = await boundary.toImage(pixelRatio: 2);
        final bytes = await screenshot.toByteData(
          format: ui.ImageByteFormat.png,
        );
        File('/private/tmp/cards-wallet-image-alignment.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        final rendered = image_lib.decodePng(bytes.buffer.asUint8List())!;
        final cardRect = tester.getRect(find.byType(CardBackgroundSurface));
        final boundaryRect = tester.getRect(find.byKey(boundaryKey));
        final sample = rendered.getPixel(
          ((cardRect.left - boundaryRect.left + 6) * 2).round(),
          ((cardRect.center.dy - boundaryRect.top) * 2).round(),
        );
        expect(sample.r, greaterThan(sample.g));
        expect(sample.r, greaterThan(sample.b));
        screenshot.dispose();
      });

      await tester.tap(find.text('Reset'));
      await tester.pumpAndSettle();
      expect(placement.toJson(), const CardImagePlacement().toJson());
      expect(tester.takeException(), isNull);
    },
  );
}
