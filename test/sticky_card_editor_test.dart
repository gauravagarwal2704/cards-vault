import 'dart:io';

import 'package:cards_wallet/data/card_designs.dart';
import 'package:cards_wallet/models/card_data.dart';
import 'package:cards_wallet/providers/theme_provider.dart';
import 'package:cards_wallet/screens/card_edit_screen.dart';
import 'package:cards_wallet/screens/manual_add_card_screen.dart';
import 'package:cards_wallet/widgets/card_background_surface.dart';
import 'package:cards_wallet/widgets/card_background_picker.dart';
import 'package:cards_wallet/widgets/card_image_alignment_editor.dart';
import 'package:cards_wallet/widgets/card_background_reveal.dart';
import 'package:cards_wallet/widgets/card_background_preview_swiper.dart';
import 'package:cards_wallet/widgets/wallet_card_face.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TestCard extends CardData {
  _TestCard()
    : super(
        encryptedCardNumber: 'unused',
        encryptedExpiryDate: 'unused',
        lastFourDigits: '1111',
        cardType: 'Visa',
      );

  @override
  Future<String> getDecryptedCardNumber() async => '4111111111111111';
  @override
  Future<String> getDecryptedExpiryDate() async => '12/30';
  @override
  Future<String?> getDecryptedCardholderName() async => 'Test User';
  @override
  Future<String?> getDecryptedCvv() async => null;
  @override
  Future<String?> getDecryptedAccountNumber() async => null;
  @override
  Future<String?> getDecryptedIfscCode() async => null;
  @override
  Future<String?> getDecryptedUpiId() async => null;
}

void main() {
  for (final editing in [false, true]) {
    testWidgets(
      '${editing ? 'Edit' : 'Add'} pins a live preview above designs',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({});
        final theme = ThemeProvider();
        addTearDown(theme.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: theme,
            child: MaterialApp(
              theme: theme.lightTheme,
              home: editing
                  ? CardEditScreen(card: _TestCard())
                  : const ManualAddCardScreen(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final preview = find.byType(WalletCardFace);
        final initialTop = tester.getTopLeft(preview).dy;
        final scroll = find.byType(CustomScrollView);
        await tester.drag(scroll, const Offset(0, -120));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(preview).dy, closeTo(initialTop - 6, 0.1));
        await tester.scrollUntilVisible(
          find.text('Card Design'),
          140,
          scrollable: find
              .descendant(of: scroll, matching: find.byType(Scrollable))
              .first,
        );
        await tester.pumpAndSettle();
        final position = tester
            .state<ScrollableState>(
              find
                  .descendant(of: scroll, matching: find.byType(Scrollable))
                  .first,
            )
            .position;
        final design = CardDesigns.getByStyle(CardDesignStyle.gradient).first;
        final designTile = find.byWidgetPredicate(
          (widget) =>
              widget is Semantics && widget.properties.label == design.name,
        );
        position.jumpTo(
          position.pixels + tester.getCenter(designTile).dy - 500,
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(CardBackgroundPreviewSwiper).hitTestable(),
          findsOneWidget,
        );
        expect(tester.getTopLeft(preview).dy, closeTo(initialTop - 6, 0.1));

        // Choosing a design lower in the form updates the still-visible card.
        await tester.tap(designTile);
        await tester.pump();
        // Image decoding runs outside the widget test's simulated clock.
        final reveal = find.byType(CardBackgroundReveal);
        await tester.runAsync(() async {
          await precacheImage(
            tester.widget<CardBackgroundReveal>(reveal).imageProvider!,
            tester.element(reveal),
          );
        });
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(preview, findsOneWidget);
        expect(find.byType(CardBackgroundReveal), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(CardBackgroundReveal),
            matching: find.byType(ClipPath),
          ),
          findsOneWidget,
        );
        await tester.pumpAndSettle();
        final surface = find.ancestor(
          of: preview,
          matching: find.byType(CardBackgroundSurface),
        );
        expect(tester.widget<CardBackgroundSurface>(surface).design, design);
        expect(
          find.byType(CardBackgroundPreviewSwiper).hitTestable(),
          findsOneWidget,
        );

        // Returning to the top settles the card back into its original position.
        position.jumpTo(0);
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(preview).dy, closeTo(initialTop, 0.1));

        // Custom-image alignment uses this same card, with no preview in the picker.
        final picker = find.byType(CardBackgroundPicker);
        final imagePath = File(design.assetPath).absolute.path;
        await tester.runAsync(() async {
          final context = tester.element(picker);
          await precacheImage(FileImage(File(imagePath)), context);
          await precacheImage(
            ResizeImage(FileImage(File(imagePath)), width: 512),
            context,
          );
        });
        tester
            .widget<CardBackgroundPicker>(picker)
            .onCustomImageChanged(imagePath);
        await tester.pump();
        tester
            .widget<CardBackgroundPicker>(picker)
            .onModeChanged(CardBackgroundMode.customImage);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(preview, findsOneWidget);
        expect(find.byType(CardImageAlignmentPreview), findsOneWidget);
        expect(
          find.descendant(
            of: picker,
            matching: find.byType(CardBackgroundSurface),
          ),
          findsNothing,
        );
        final zoom = find.byKey(const ValueKey('card-image-zoom'));
        position.jumpTo(position.pixels + tester.getCenter(zoom).dy - 500);
        await tester.pumpAndSettle();
        await tester.drag(zoom, const Offset(45, 0));
        await tester.pumpAndSettle();
        final liveSurface = find.ancestor(
          of: preview,
          matching: find.byType(CardBackgroundSurface),
        );
        expect(
          tester
              .widget<CardBackgroundSurface>(liveSurface)
              .backgroundImagePlacement
              .zoom,
          greaterThan(1),
        );
        final alignment = find.byKey(
          const ValueKey('card-image-alignment-preview'),
        );
        expect(
          tester.widget<GestureDetector>(alignment).onScaleStart,
          isNotNull,
        );
        final beforeDrag = tester
            .widget<CardBackgroundSurface>(liveSurface)
            .backgroundImagePlacement
            .x;
        await tester.timedDrag(
          alignment,
          const Offset(60, -20),
          const Duration(milliseconds: 300),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CardBackgroundSurface>(liveSurface)
              .backgroundImagePlacement
              .x,
          lessThan(beforeDrag),
        );
        await tester.tap(find.text('Reset'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<CardBackgroundSurface>(liveSurface)
              .backgroundImagePlacement
              .zoom,
          1,
        );
        expect(preview, findsOneWidget);
        tester.widget<CardBackgroundPicker>(picker).onCustomImageChanged(null);
        await tester.pumpAndSettle();
        expect(find.byType(CardImageAlignmentPreview), findsNothing);
        expect(find.byType(CardImageAlignmentEditor), findsNothing);
        position.jumpTo(0);
        await tester.pumpAndSettle();

        // A visible keyboard still leaves space for the form and preview.
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        addTearDown(tester.view.resetViewInsets);
        await tester.pumpAndSettle();
        expect(
          find.byType(CardBackgroundPreviewSwiper).hitTestable(),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
