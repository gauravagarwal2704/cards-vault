import 'package:flutter/services.dart';

class LocalCardScanResult {
  final String? pan;
  final String? imagePath;
  final String? source;
  final String? cancellationReason;

  const LocalCardScanResult({
    this.pan,
    this.imagePath,
    this.source,
    this.cancellationReason,
  });

  bool get completed => pan != null || imagePath != null;
  bool get fromGallery => source == 'gallery';
}

class LocalCardScanService {
  const LocalCardScanService();

  static const MethodChannel _channel = MethodChannel('cards_wallet/card_scan');

  Future<LocalCardScanResult> scan() async {
    final payload = await _channel.invokeMapMethod<Object?, Object?>(
      'scanCard',
    );
    if (payload == null) {
      return const LocalCardScanResult(cancellationReason: 'unavailable');
    }

    final status = payload['status']?.toString();
    if (status != 'completed') {
      return LocalCardScanResult(
        cancellationReason: payload['reason']?.toString() ?? 'closed',
      );
    }

    final pan = payload['pan']?.toString().replaceAll(RegExp(r'\D'), '');
    return LocalCardScanResult(
      pan: pan == null || pan.isEmpty ? null : pan,
      imagePath: payload['imagePath']?.toString(),
      source: payload['source']?.toString(),
    );
  }
}
