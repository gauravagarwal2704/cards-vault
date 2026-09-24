import 'dart:io';

import 'package:cards_wallet/data/card_designs.dart';
import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/utils/card_contrast.dart';
import 'package:cards_wallet/widgets/card_background_picker.dart';
import 'package:cards_wallet/widgets/card_background_preview_swiper.dart';
import 'package:cards_wallet/widgets/card_background_surface.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image_lib;

void main() {
  test('catalog mirrors every supplied Figma card frame', () {
    expect(CardDesigns.gradient, hasLength(12));
    expect(CardDesigns.dualTone, hasLength(12));
    expect(CardDesigns.abstract, hasLength(8));
    expect(CardDesigns.designer, hasLength(18));
    expect(CardDesigns.gradientBlur, hasLength(8));
    expect(CardDesigns.glassmorphism, hasLength(2));
    expect(CardDesigns.monochrome, hasLength(2));
    expect(CardDesigns.image, hasLength(6));
    expect(CardDesigns.all, hasLength(68));

    for (final design in CardDesigns.all) {
      expect(
        File(design.sourceSvgPath).existsSync(),
        isTrue,
        reason: design.name,
      );
      expect(File(design.assetPath).existsSync(), isTrue, reason: design.name);
      expect(
        design.foregroundColor,
        anyOf(CardContrast.ivory, CardContrast.charcoal),
        reason: design.name,
      );
      expect(design.foregroundColor, isNot(Colors.white));
      expect(design.foregroundColor, isNot(Colors.black));
    }
  });

  test('legacy Designer IDs migrate without changing saved cards', () {
    expect(CardDesigns.getById('designer_01')?.name, 'Abstract/01');
    expect(CardDesigns.getById('designer_08')?.name, 'Abstract/08');
    expect(CardDesigns.getById('designer_09')?.name, 'Designer 2.0/01');
    expect(CardDesigns.getById('designer_26')?.name, 'Designer 2.0/18');
  });

  test('card background cycling wraps within the selected category', () {
    final first = CardDesigns.gradient.first;
    final last = CardDesigns.gradient.last;

    expect(
      CardDesigns.cycle(
        style: CardDesignStyle.gradient,
        currentId: first.id,
        direction: -1,
      ).id,
      last.id,
    );
    expect(
      CardDesigns.cycle(
        style: CardDesignStyle.gradient,
        currentId: last.id,
        direction: 1,
      ).id,
      first.id,
    );
  });

  testWidgets('preview swipes cycle backward and forward', (tester) async {
    final directions = <int>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              height: 220,
              child: CardBackgroundPreviewSwiper(
                enabled: true,
                backgroundKey: 'preview',
                onCycle: directions.add,
                child: const ColoredBox(color: Colors.blue),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byType(CardBackgroundPreviewSwiper),
      const Offset(-80, 0),
    );
    await tester.pumpAndSettle();
    await tester.drag(
      find.byType(CardBackgroundPreviewSwiper),
      const Offset(80, 0),
    );
    await tester.pumpAndSettle();

    expect(directions, [1, -1]);
  });

  test('custom card background settings survive JSON round trip', () {
    final card = CardData(
      encryptedCardNumber: 'encrypted-number',
      encryptedExpiryDate: 'encrypted-expiry',
      lastFourDigits: '4242',
      cardType: 'Visa',
      id: 'card-id',
      customGradientStartColor: 0xFF123456,
      customGradientEndColor: 0xFFABCDEF,
      customGradientAngle: 72,
      customBackgroundImagePath: '/documents/background.jpg',
      backgroundImageBlur: 7.5,
    );

    final restored = CardData.fromJson(card.toJson());

    expect(restored.customGradientStartColor, 0xFF123456);
    expect(restored.customGradientEndColor, 0xFFABCDEF);
    expect(restored.customGradientAngle, 72);
    expect(restored.customBackgroundImagePath, '/documents/background.jpg');
    expect(restored.backgroundImageBlur, 7.5);
  });

  testWidgets('blur affects an Image design but leaves card content sharp', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 350,
          height: 220,
          child: CardBackgroundSurface(
            design: CardDesigns.image.first,
            backgroundImageBlur: 8,
            fallbackPrimaryColor: Colors.blueGrey,
            fallbackSecondaryColor: Colors.black,
            borderRadius: BorderRadius.circular(16),
            showShadow: false,
            child: const Text('**** 4242'),
          ),
        ),
      ),
    );

    final filter = find.byType(ImageFiltered);
    expect(filter, findsOneWidget);
    expect(
      find.descendant(of: filter, matching: find.text('**** 4242')),
      findsNothing,
    );
  });

  testWidgets('blur affects a custom image background', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 350,
          height: 220,
          child: CardBackgroundSurface(
            customBackgroundImagePath: '/missing/background.jpg',
            backgroundImageBlur: 6,
            fallbackPrimaryColor: Colors.blueGrey,
            fallbackSecondaryColor: Colors.black,
            borderRadius: BorderRadius.circular(16),
            showShadow: false,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('card backgrounds decode to a stable rendered-size cache width', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 350,
            height: 220,
            child: CardBackgroundSurface(
              design: CardDesigns.image.first,
              customBackgroundImagePath: '/missing/background.jpg',
              fallbackPrimaryColor: Colors.blueGrey,
              fallbackSecondaryColor: Colors.black,
              borderRadius: BorderRadius.circular(16),
              showShadow: false,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final images = tester.widgetList<Image>(find.byType(Image)).toList();
    expect(images, hasLength(2));
    for (final image in images) {
      expect(image.image, isA<ResizeImage>());
      final resized = image.image as ResizeImage;
      expect(resized.width, 1280);
      expect(resized.height, isNull);
    }
  });

  testWidgets('blur control is offered for Image designs and custom images', (
    tester,
  ) async {
    Future<void> pumpPicker(CardBackgroundMode mode, CardDesignStyle style) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: CardBackgroundPicker(
                mode: mode,
                selectedStyle: style,
                selectedDesign: style == CardDesignStyle.image
                    ? CardDesigns.image.first
                    : null,
                gradientStart: Colors.blue,
                gradientEnd: Colors.purple,
                gradientAngle: 135,
                customImagePath: null,
                backgroundImageBlur: 5,
                onModeChanged: (_) {},
                onStyleChanged: (_) {},
                onDesignChanged: (_) {},
                onGradientChanged: (_, _) {},
                onGradientAngleChanged: (_) {},
                onCustomImageChanged: (_) {},
                onBackgroundImageBlurChanged: (_) {},
              ),
            ),
          ),
        ),
      );
    }

    await pumpPicker(CardBackgroundMode.catalog, CardDesignStyle.image);
    expect(find.text('Background blur'), findsOneWidget);

    await pumpPicker(CardBackgroundMode.customImage, CardDesignStyle.gradient);
    expect(find.text('Background blur'), findsOneWidget);

    await pumpPicker(CardBackgroundMode.catalog, CardDesignStyle.gradient);
    expect(find.text('Background blur'), findsNothing);
  });

  testWidgets('blur is ignored outside the Image design category', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 350,
          height: 220,
          child: CardBackgroundSurface(
            design: CardDesigns.gradient.first,
            backgroundImageBlur: 8,
            fallbackPrimaryColor: Colors.blueGrey,
            fallbackSecondaryColor: Colors.black,
            borderRadius: BorderRadius.circular(16),
            showShadow: false,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    expect(find.byType(ImageFiltered), findsNothing);
  });

  test('Gradient 2.0 previews contain no hard rasterization seams', () {
    for (final number in [2, 3, 4, 6, 7, 8]) {
      final path =
          'assets/card_backgrounds/gradient_blur/${number.toString().padLeft(2, '0')}.webp';
      final image = image_lib.decodeImage(File(path).readAsBytesSync());
      expect(image, isNotNull, reason: path);

      final (columnJump, rowJump) = _largestInteriorEdgeJump(image!);
      expect(columnJump, lessThan(3), reason: '$path has a vertical seam');
      expect(rowJump, lessThan(3), reason: '$path has a horizontal seam');
    }
  });

  testWidgets('every catalog background decodes in the shared card renderer', (
    tester,
  ) async {
    for (final design in CardDesigns.all) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 350,
              height: 220,
              child: CardBackgroundSurface(
                design: design,
                fallbackPrimaryColor: design.primaryColor,
                fallbackSecondaryColor: design.secondaryColor,
                borderRadius: BorderRadius.circular(16),
                showShadow: false,
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: design.name);
    }
  });
}

(double, double) _largestInteriorEdgeJump(image_lib.Image image) {
  const margin = 20;
  var largestColumnJump = 0.0;
  var largestRowJump = 0.0;

  for (var x = margin; x < image.width - margin; x++) {
    var total = 0.0;
    for (var y = margin; y < image.height - margin; y++) {
      total += _pixelDifference(image.getPixel(x - 1, y), image.getPixel(x, y));
    }
    final average = total / (image.height - margin * 2);
    if (average > largestColumnJump) largestColumnJump = average;
  }

  for (var y = margin; y < image.height - margin; y++) {
    var total = 0.0;
    for (var x = margin; x < image.width - margin; x++) {
      total += _pixelDifference(image.getPixel(x, y - 1), image.getPixel(x, y));
    }
    final average = total / (image.width - margin * 2);
    if (average > largestRowJump) largestRowJump = average;
  }

  return (largestColumnJump, largestRowJump);
}

double _pixelDifference(image_lib.Pixel left, image_lib.Pixel right) {
  return ((left.r - right.r).abs() +
          (left.g - right.g).abs() +
          (left.b - right.b).abs()) /
      3;
}
