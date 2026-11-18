import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:image/image.dart' as img;

import '../data/banks.dart';
import '../data/card_designs.dart';
import '../models/card_data.dart';
import '../utils/card_contrast.dart';
import '../utils/card_network_utils.dart';
import '../widgets/card_background_surface.dart';
import '../widgets/card_network_logo.dart';
import 'storage_path_guard.dart';

/// Renders the actual shared background, never a wallet card containing fields.
/// Custom images are used only from a contained private file path.
class WidgetCardArtwork {
  static const width = 512;
  static const height = 323;

  static Future<Map<String, Object>> render(
    CardData card, {
    required Color fallbackPrimary,
    required Color fallbackSecondary,
    bool includeCustomImage = false,
  }) async {
    final bank = Banks.getById(card.bankId ?? '');
    final design = card.designId == null
        ? null
        : CardDesigns.getById(card.designId!);
    final primary = card.customGradientStartColor != null
        ? Color(card.customGradientStartColor!)
        : design?.primaryColor ?? bank?.primaryColor ?? fallbackPrimary;
    final secondary = card.customGradientEndColor != null
        ? Color(card.customGradientEndColor!)
        : design?.secondaryColor ?? bank?.secondaryColor ?? fallbackSecondary;
    final path = card.customBackgroundImagePath;
    final hasCustom =
        includeCustomImage &&
        path != null &&
        path.isNotEmpty &&
        await _contained(path);
    final foreground =
        design?.foregroundColor ??
        (hasCustom
            ? CardContrast.ivory
            : CardContrast.bestForeground([primary, secondary]));
    final ImageProvider? provider = hasCustom
        ? FileImage(File(path))
        : design != null
        ? AssetImage(design.assetPath)
        : null;
    if (provider != null) {
      await _warm(ResizeImage.resizeIfNeeded(512, null, provider));
    }
    final image = await _backgroundImage(
      CardBackgroundSurface(
        design: design,
        customGradientStartColor: card.customGradientStartColor,
        customGradientEndColor: card.customGradientEndColor,
        customGradientAngle: card.customGradientAngle,
        customBackgroundImagePath: hasCustom ? path : null,
        backgroundImageBlur: card.backgroundImageBlur,
        backgroundImagePlacement: card.backgroundImagePlacement,
        fallbackPrimaryColor: primary,
        fallbackSecondaryColor: secondary,
        borderRadius: BorderRadius.zero,
        showShadow: false,
        child:
            card.cardType.toLowerCase() == 'mastercard' &&
                design == null &&
                card.customGradientStartColor == null &&
                !hasCustom
            ? const MastercardBackgroundPattern()
            : const SizedBox.shrink(),
      ),
    );
    try {
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      // Opaque artwork only, bounded to a small JPEG rather than full-resolution photos.
      final jpeg = await compute(
        _encodeBackground,
        rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
      );
      final logo = await _logo(card, foreground);
      Uint8List? bankLogo;
      try {
        if (bank != null) bankLogo = await _bankLogo(bank, foreground);
      } catch (_) {
        // An unreadable logo falls back to the catalog bank name.
      }
      return {
        'background': Uint8List.fromList(jpeg),
        'foreground': foreground.toARGB32(),
        'logo': ?logo,
        'bankLogo': ?bankLogo,
        'customArtwork': hasCustom,
      };
    } finally {
      image.dispose();
    }
  }

  static Future<bool> _contained(String path) async {
    try {
      return await isContainedInStorageDirectory('card_backgrounds', path);
    } catch (_) {
      return false;
    }
  }

  static Future<void> _warm(ImageProvider provider) async {
    final stream = provider.resolve(const ImageConfiguration());
    final ready = Completer<void>();
    late ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        info.dispose();
        if (!ready.isCompleted) ready.complete();
      },
      onError: (Object error, StackTrace? stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
      },
    );
    stream.addListener(listener);
    try {
      await ready.future;
    } finally {
      stream.removeListener(listener);
    }
  }

  static Future<ui.Image> _backgroundImage(Widget surface) async {
    final boundary = RenderRepaintBoundary();
    final pipeline = PipelineOwner();
    final focus = FocusManager();
    final owner = BuildOwner(focusManager: focus);
    const size = Size(512, 323);
    final view = RenderView(
      view: WidgetsBinding.instance.platformDispatcher.views.first,
      configuration: const ViewConfiguration(
        logicalConstraints: BoxConstraints.tightFor(width: 512, height: 323),
        physicalConstraints: BoxConstraints.tightFor(width: 512, height: 323),
        devicePixelRatio: 1,
      ),
      child: RenderPositionedBox(child: boundary),
    );
    pipeline.rootNode = view;
    view.prepareInitialFrame();
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: MediaQuery(
        data: const MediaQueryData(size: size, devicePixelRatio: 1),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox.fromSize(size: size, child: surface),
        ),
      ),
    ).attachToRenderTree(owner);
    try {
      owner.buildScope(root);
      pipeline.flushLayout();
      pipeline.flushCompositingBits();
      pipeline.flushPaint();
      return await boundary.toImage();
    } finally {
      root.update(RenderObjectToWidgetAdapter<RenderBox>(container: boundary));
      owner.buildScope(root);
      owner.finalizeTree();
      pipeline.rootNode = null;
      view.dispose();
      pipeline.dispose();
      focus.dispose();
    }
  }

  static Future<Uint8List?> _logo(CardData card, Color foreground) async {
    final network = CardNetworkUtils.networkFromCardType(card.cardType);
    final path = CardNetworkLogo.assetPath(network);
    if (path == null) return null;
    final picture = await vg.loadPicture(SvgAssetLoader(path), null);
    try {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const side = 192;
      final fit = applyBoxFit(
        BoxFit.contain,
        picture.size,
        const Size.square(192),
      );
      final rect = Alignment.center.inscribe(
        fit.destination,
        const Rect.fromLTWH(0, 0, 192, 192),
      );
      canvas.saveLayer(
        null,
        Paint()
          ..colorFilter =
              foreground == CardContrast.ivory &&
                  !['mastercard', 'amex', 'gpay'].contains(network.name)
              ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
              : null,
      );
      canvas.translate(rect.left, rect.top);
      canvas.scale(
        rect.width / picture.size.width,
        rect.height / picture.size.height,
      );
      canvas.drawPicture(picture.picture);
      canvas.restore();
      final result = recorder.endRecording();
      final image = await result.toImage(side, side);
      result.dispose();
      try {
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final decoded = img.Image.fromBytes(
          width: side,
          height: side,
          bytes: rgba.buffer,
          bytesOffset: rgba.offsetInBytes,
          numChannels: 4,
        );
        final trimmed = img.trim(decoded, mode: img.TrimMode.transparent);
        // Use the Mastercard symbol without the separate wordmark underneath.
        final mark = network.name == 'mastercard'
            ? img.copyCrop(
                trimmed,
                x: 0,
                y: 0,
                width: trimmed.width,
                height: (trimmed.width * .625).round().clamp(1, trimmed.height),
              )
            : trimmed;
        return Uint8List.fromList(img.encodePng(mark));
      } finally {
        image.dispose();
      }
    } finally {
      picture.picture.dispose();
    }
  }

  static Future<Uint8List?> _bankLogo(BankInfo bank, Color foreground) async {
    final large = bank.logoPathLarge;
    final path = large != null && !large.endsWith('/dummy.svg')
        ? large
        : bank.logoPathSmall;
    if (path == null || path.endsWith('/dummy.svg')) return null;
    final picture = await vg.loadPicture(SvgAssetLoader(path), null);
    try {
      const width = 220;
      const height = 56;
      final isWide = picture.size.width / picture.size.height > 1.8;
      final plate = isWide && bank.id != 'federal';
      final bounds = Rect.fromLTWH(
        plate ? 8 : 0,
        plate ? 8 : 0,
        plate ? 204 : 220,
        plate ? 40 : 56,
      );
      final fit = applyBoxFit(BoxFit.contain, picture.size, bounds.size);
      final target = Alignment.center.inscribe(fit.destination, bounds);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      if (plate) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              target.left - 7,
              target.top - 5,
              target.width + 14,
              target.height + 10,
            ),
            const Radius.circular(5),
          ),
          Paint()..color = Colors.white,
        );
      }
      canvas.saveLayer(
        null,
        Paint()
          ..colorFilter =
              !plate &&
                  bank.id != 'federal' &&
                  bank.id != 'amex' &&
                  foreground.computeLuminance() > .5
              ? const ColorFilter.mode(Colors.white, BlendMode.srcIn)
              : null,
      );
      canvas.translate(target.left, target.top);
      canvas.scale(
        target.width / picture.size.width,
        target.height / picture.size.height,
      );
      canvas.drawPicture(picture.picture);
      canvas.restore();
      final drawing = recorder.endRecording();
      final image = await drawing.toImage(width, height);
      drawing.dispose();
      try {
        final rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final decoded = img.Image.fromBytes(
          width: width,
          height: height,
          bytes: rgba.buffer,
          bytesOffset: rgba.offsetInBytes,
          numChannels: 4,
        );
        return Uint8List.fromList(
          img.encodePng(img.trim(decoded, mode: img.TrimMode.transparent)),
        );
      } finally {
        image.dispose();
      }
    } finally {
      picture.picture.dispose();
    }
  }
}

Uint8List _encodeBackground(Uint8List rgba) {
  final image = img.Image.fromBytes(
    width: WidgetCardArtwork.width,
    height: WidgetCardArtwork.height,
    bytes: rgba.buffer,
    bytesOffset: rgba.offsetInBytes,
    numChannels: 4,
  );
  var jpeg = img.encodeJpg(image, quality: 90);
  if (jpeg.length > 131072) jpeg = img.encodeJpg(image, quality: 70);
  return Uint8List.fromList(jpeg);
}
