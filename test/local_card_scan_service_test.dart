import 'package:cards_wallet/services/local_card_scan_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a gallery image is a completed local scan without a verified PAN', () {
    const result = LocalCardScanResult(
      imagePath: '/tmp/selected-card.image',
      source: 'gallery',
    );

    expect(result.completed, isTrue);
    expect(result.pan, isNull);
    expect(result.fromGallery, isTrue);
  });

  test('a canceled local scan has neither PAN nor image', () {
    const result = LocalCardScanResult(cancellationReason: 'closed');

    expect(result.completed, isFalse);
  });
}
