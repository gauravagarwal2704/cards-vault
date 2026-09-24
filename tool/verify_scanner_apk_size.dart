import 'dart:io';

const scannerCompressedBudgetBytes = 5 * 1024 * 1024;

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: dart run tool/verify_scanner_apk_size.dart <apk>');
    exitCode = 64;
    return;
  }

  final apk = File(arguments.single);
  if (!apk.existsSync()) {
    stderr.writeln('APK not found: ${apk.path}');
    exitCode = 66;
    return;
  }

  final listing = await Process.run('unzip', ['-lv', apk.path]);
  if (listing.exitCode != 0) {
    stderr.write(listing.stderr);
    exitCode = listing.exitCode;
    return;
  }

  var scannerCompressedBytes = 0;
  final abis = <String>{};
  var hasModel = false;
  var hasLiteRt = false;
  var hasLiteRtJni = false;
  var hasGpuAccelerator = false;

  for (final rawLine in (listing.stdout as String).split('\n')) {
    final columns = rawLine.trim().split(RegExp(r'\s+'));
    if (columns.length < 8 || int.tryParse(columns[0]) == null) continue;
    final compressedBytes = int.tryParse(columns[2]);
    if (compressedBytes == null) continue;
    final path = columns.last;

    final abiMatch = RegExp(r'^lib/([^/]+)/').firstMatch(path);
    if (abiMatch != null) abis.add(abiMatch.group(1)!);

    final isModel = path == 'assets/darknite_1_1_1_16.tflite';
    final isLiteRt = path.endsWith('/libLiteRt.so');
    final isLiteRtJni = path.endsWith('/liblitert_jni.so');
    if (isModel || isLiteRt || isLiteRtJni) {
      scannerCompressedBytes += compressedBytes;
    }
    hasModel |= isModel;
    hasLiteRt |= isLiteRt;
    hasLiteRtJni |= isLiteRtJni;
    hasGpuAccelerator |= path.endsWith('/libLiteRtClGlAccelerator.so');
  }

  final failures = <String>[];
  if (abis.length != 1) {
    failures.add('release APK must contain exactly one ABI; found $abis');
  }
  if (!hasModel || !hasLiteRt || !hasLiteRtJni) {
    failures.add('release APK is missing a required scanner component');
  }
  if (hasGpuAccelerator) {
    failures.add('unused LiteRT GPU accelerator is packaged');
  }
  if (scannerCompressedBytes > scannerCompressedBudgetBytes) {
    failures.add(
      'scanner payload is $scannerCompressedBytes bytes; '
      'budget is $scannerCompressedBudgetBytes',
    );
  }

  stdout.writeln(
    'scanner compressed payload: $scannerCompressedBytes bytes; ABI: '
    '${abis.isEmpty ? 'none' : abis.join(',')}',
  );
  if (failures.isNotEmpty) {
    failures.forEach(stderr.writeln);
    exitCode = 1;
  }
}
