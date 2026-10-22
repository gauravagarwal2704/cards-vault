import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:cards_wallet/widgets/card_background_reveal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _DelayedImageProvider extends ImageProvider<_DelayedImageProvider> {
  final decoded = Completer<ImageInfo>();

  @override
  Future<_DelayedImageProvider> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
    _DelayedImageProvider key,
    ImageDecoderCallback decode,
  ) => OneFrameImageStreamCompleter(decoded.future);
}

void main() {
  Widget preview(
    int selection, {
    bool reduceMotion = false,
    ImageProvider? imageProvider,
    Duration duration = const Duration(milliseconds: 400),
  }) => MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Center(
        child: SizedBox(
          width: 320,
          height: 200,
          child: CardBackgroundReveal(
            backgroundKey: selection,
            imageProvider: imageProvider,
            duration: duration,
            child: ColoredBox(
              key: ValueKey(selection),
              color: [Colors.blue, Colors.red, Colors.green][selection],
            ),
          ),
        ),
      ),
    ),
  );

  testWidgets(
    'circle expands over the previous background and then clears it',
    (tester) async {
      await tester.pumpWidget(preview(0));
      expect(find.byType(ClipPath), findsNothing);
      await tester.pumpWidget(preview(1));
      expect(find.byKey(const ValueKey(0)), findsOneWidget);
      expect(find.byKey(const ValueKey(1)), findsOneWidget);

      Path clip() => tester
          .widget<ClipPath>(find.byType(ClipPath))
          .clipper!
          .getClip(const Size(320, 200));
      expect(clip().getBounds().width, 0);
      await tester.pump(const Duration(milliseconds: 80));
      final earlyCircle = clip().getBounds();
      expect(earlyCircle.width, greaterThan(0));
      expect(earlyCircle.width, closeTo(earlyCircle.height, 0.01));
      expect(
        const Rect.fromLTWH(0, 0, 320, 200).contains(earlyCircle.center),
        isTrue,
      );
      await tester.pump(const Duration(milliseconds: 319));
      final lateCircle = clip();
      expect(lateCircle.getBounds().width, greaterThan(earlyCircle.width));
      // The radius reaches the farthest card corner before the final cleanup.
      for (final corner in [
        const Offset(1, 1),
        const Offset(319, 1),
        const Offset(1, 199),
        const Offset(319, 199),
      ]) {
        expect(lateCircle.contains(corner), isTrue);
      }
      await tester.pumpAndSettle();
      expect(find.byType(ClipPath), findsNothing);
      expect(find.byKey(const ValueKey(0)), findsNothing);
      expect(find.byKey(const ValueKey(1)), findsOneWidget);
    },
  );

  testWidgets('duration changes apply to an already mounted preview', (
    tester,
  ) async {
    await tester.pumpWidget(
      preview(0, duration: const Duration(milliseconds: 920)),
    );
    final originalState = tester.state(find.byType(CardBackgroundReveal));
    await tester.pumpWidget(
      preview(0, duration: const Duration(milliseconds: 240)),
    );
    expect(
      tester.state(find.byType(CardBackgroundReveal)),
      same(originalState),
    );
    await tester.pumpWidget(
      preview(1, duration: const Duration(milliseconds: 240)),
    );
    await tester.pump(const Duration(milliseconds: 239));
    expect(find.byType(ClipPath), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 17));
    expect(find.byType(ClipPath), findsNothing);
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
  });

  testWidgets('rapid selections finish on the latest background', (
    tester,
  ) async {
    await tester.pumpWidget(preview(0));
    await tester.pumpWidget(preview(1));
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester
        .widget<ClipPath>(find.byType(ClipPath))
        .clipper!
        .getClip(const Size(320, 200))
        .getBounds();
    await tester.pumpWidget(preview(2));
    final after = tester
        .widget<ClipPath>(find.byType(ClipPath))
        .clipper!
        .getClip(const Size(320, 200))
        .getBounds();
    expect(after, before);
    expect(find.byKey(const ValueKey(0)), findsOneWidget);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
    expect(find.byKey(const ValueKey(2)), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(find.byKey(const ValueKey(1)), findsNothing);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('image decoding finishes before the reveal starts', (
    tester,
  ) async {
    final provider = _DelayedImageProvider();
    await tester.pumpWidget(preview(0));
    await tester.pumpWidget(preview(1, imageProvider: provider));
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey(0)), findsOneWidget);
    expect(find.byKey(const ValueKey(1)), findsNothing);
    expect(find.byType(ClipPath), findsNothing);

    final image = await tester.runAsync(() => createTestImage());
    provider.decoded.complete(ImageInfo(image: image!));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byType(ClipPath), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
  });

  testWidgets('a stale image load cannot replace a newer selection', (
    tester,
  ) async {
    final provider = _DelayedImageProvider();
    await tester.pumpWidget(preview(0));
    await tester.pumpWidget(preview(1, imageProvider: provider));
    await tester.pumpWidget(preview(2));
    await tester.pumpAndSettle();
    final image = await tester.runAsync(() => createTestImage());
    provider.decoded.complete(ImageInfo(image: image!));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey(1)), findsNothing);
    expect(find.byKey(const ValueKey(2)), findsOneWidget);
    expect(find.byType(ClipPath), findsNothing);
  });

  testWidgets('reduced motion applies designs immediately', (tester) async {
    await tester.pumpWidget(preview(0, reduceMotion: true));
    await tester.pumpWidget(preview(1, reduceMotion: true));
    expect(find.byType(ClipPath), findsNothing);
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(find.byKey(const ValueKey(1)), findsOneWidget);
  });

  testWidgets('enabling reduced motion completes an active reveal', (
    tester,
  ) async {
    await tester.pumpWidget(preview(0));
    await tester.pumpWidget(preview(1));
    await tester.pump(const Duration(milliseconds: 80));
    await tester.pumpWidget(preview(1, reduceMotion: true));
    expect(find.byType(ClipPath), findsNothing);
    expect(find.byKey(const ValueKey(0)), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
