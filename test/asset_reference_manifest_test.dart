import 'dart:io';

import 'package:cards_wallet/data/banks.dart';
import 'package:cards_wallet/data/card_designs.dart';
import 'package:cards_wallet/models/app_icon_option.dart';
import 'package:cards_wallet/widgets/bank_logo.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every bundled runtime asset is referenced by a catalog', () {
    final referenced = <String>{
      for (final option in AppIconCatalog.options) option.assetPath,
      for (final bank in Banks.all)
        ...[
          bank.logoPath,
          bank.logoPathSmall,
          bank.logoPathLarge,
        ].whereType<String>(),
      BankLogo.dummyLogoSmall,
      for (final design in CardDesigns.all) design.assetPath,
      ..._networkAssets,
      ..._aboutAssets,
    };

    final bundled = Directory('assets')
        .listSync(recursive: true)
        .whereType<File>()
        .map((file) => file.path)
        .where((path) => !path.startsWith('assets/fonts/'))
        .toSet();

    expect(bundled.difference(referenced), isEmpty, reason: 'unused assets');
    expect(referenced.difference(bundled), isEmpty, reason: 'missing assets');
  });

  test('runtime asset files do not contain byte-identical duplicates', () {
    final byDigest = <Digest, List<String>>{};
    for (final file in Directory(
      'assets',
    ).listSync(recursive: true).whereType<File>()) {
      if (file.path.startsWith('assets/fonts/')) continue;
      final digest = sha256.convert(file.readAsBytesSync());
      byDigest.putIfAbsent(digest, () => []).add(file.path);
    }

    expect(
      byDigest.values.where((paths) => paths.length > 1),
      isEmpty,
      reason: 'Duplicate files should share one canonical asset path.',
    );
  });
}

const _networkAssets = {
  'assets/networks/visa.svg',
  'assets/networks/mastercard.svg',
  'assets/networks/amex.svg',
  'assets/networks/amex-small.svg',
  'assets/networks/discover.svg',
  'assets/networks/jcb.svg',
  'assets/networks/diners-club.svg',
  'assets/networks/union-pay.svg',
  'assets/networks/rupay.svg',
  'assets/networks/maestro.svg',
};

const _aboutAssets = {'assets/branding/github-mark.svg'};
