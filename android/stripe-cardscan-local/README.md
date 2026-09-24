# Local Android CardScan runtime

This directory is an isolated, vendored fork of the Android camera, OCR model,
and local LiteRT adapter code derived from Stripe Android SDK `v21.28.1`.
`UPSTREAM.properties` pins the annotated tag and its resolved commit, while
`LOCAL_DELTAS.md` inventories every intentionally divergent production area.
Gradle validates the provenance file before configuring these local modules and
publishes them only under CardVault's private vendored module identity.

Only the offline CardScan pipeline is compiled. The Stripe networking,
analytics/diagnostic reporter, payment modules, Dagger graph, fragment API,
and `INTERNET` permission are intentionally excluded. The scanner uses the
standalone `com.google.ai.edge.litert:litert` runtime rather than the Google
Play Services runtime. It uses
CameraX `ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST`, requires agreement across
three Luhn-valid PAN detections, and has a 20-second session timeout.

## LiteRT dependency decision

LiteRT is required, not an orphaned transitive dependency. `CardScanFlow`
loads `darknite_1_1_1_16.tflite`; `SSDOcr.Factory` creates an
`InterpreterWrapperImpl`; and every OCR inference calls the LiteRT Interpreter
API. Removing the runtime would disable both live and gallery PAN recognition.

The runtime is pinned to `com.google.ai.edge.litert:litert:2.2.0`, the supported
Google Maven release reviewed on 2026-08-26. The scanner uses only the CPU
Interpreter API (its obsolete NNAPI toggle has been removed), so the app excludes the optional
`libLiteRtClGlAccelerator.so` shipped in LiteRT 2.x. The model remains bundled
locally; optional LiteRT model-delivery foreground-service permissions are
removed during manifest merge.

## Upstream review and upgrade procedure

Review this fork at least every 90 days, on every Stripe Android/CardScan or
LiteRT security release, and before raising Android compile/target SDK levels.
The owner performing the review must:

1. Read Stripe's release notes and security advisories from the current pinned
   tag through the candidate tag. Treat CardScan, camera, image decode,
   lifecycle, coroutine, and ML-runtime changes as security-relevant.
2. Resolve the candidate annotated tag to its full commit SHA and update
   `UPSTREAM.properties`; never pin a branch or an unverified moving ref.
3. Compare the four upstream source roots against the local modules and update
   every entry in `LOCAL_DELTAS.md`. Prefer upstreaming generally useful fixes;
   otherwise keep the CardVault delta narrowly isolated and documented.
4. Reapply deltas one category at a time: dependency/telemetry removal,
   lifecycle cleanup, result bridge, gallery import, frame retention, then
   LiteRT adaptation. Do not replace the fork wholesale.
5. Run `flutter test test/scanner_upstream_strategy_test.dart`, the native unit
   and instrumentation tests, `flutter analyze`, the full Flutter test suite,
   and a split-ABI release build. Inspect the merged manifest and APK contents
   for network/telemetry dependencies and optional native runtimes.
6. On a physical arm64 device, smoke-test live scanning, gallery scanning,
   cancellation, timeout, repeated open/close, background/resume, and a card
   that is not recognized. Record the reviewer and date in the release change.

If a critical upstream fix cannot be safely ported and verified, disable the
scanner feature for that release rather than shipping an unreviewed fork.

Among PAN-positive preview frames, only the sharpest matching crop is retained
in memory. That single accepted crop is written losslessly and temporarily so
the app's local Tesseract pass can attempt expiry and cardholder-name
extraction. Rejected preview frames are recycled after inference, and the
temporary accepted crop is deleted immediately after text OCR.

Upstream: https://github.com/stripe/stripe-android/tree/v21.28.1

Pinned commit: `608adb7515db07c758303bd95b9013e063316f8e`

License: Stripe's MIT license is included in `LICENSE`.
