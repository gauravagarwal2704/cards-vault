# CardVault scanner delta inventory

Baseline: Stripe Android `v21.28.1`, commit
`608adb7515db07c758303bd95b9013e063316f8e`.

This file describes intentional production differences. Build metadata, API
snapshots, upstream unit-test fixtures, and documentation omitted from the
vendored runtime are not copied unless CardVault needs them to compile,
operate, or preserve license/provenance obligations.

## Module isolation and dependency surface

- All four modules have standalone Android build files and CardVault namespaces,
  Java/Kotlin 17 configuration, and only the dependencies required by the
  offline scanner.
- Stripe networking, analytics/event reporting, Dagger injection, public sheet
  and fragment APIs, `stripe-core` storage, and the `INTERNET` permission are
  excluded.
- Resources required at runtime are colocated under each module's
  `src/main/res`; Stripe repository build infrastructure is deliberately not
  vendored.
- `stripecardscan/build.gradle` assigns a CardVault-only group/version so the
  fork cannot be confused with Stripe's published artifact.

## Camera module

- `camera-core/.../CameraAdapter.kt`: adds idempotent explicit destruction when
  lifecycle detachment occurs before `ON_DESTROY`.
- `camera-core/.../CameraXAdapter.kt`: clears analyzers, unbinds every use case,
  shuts down the executor safely, and releases camera references.
- `camera-core/.../CameraPermissionCheckingActivity.kt`: replaces the removed
  `stripe-core` storage wrapper with app-private Android `SharedPreferences`.

## ML adapter modules

- `ml-core-base/.../InterpreterOptionsWrapper.kt`: removes the obsolete NNAPI
  option from the fork's CPU-only contract.
- `ml-core-cardscan/.../InterpreterWrapperImpl.kt`: uses the standalone pinned
  LiteRT CPU interpreter and no longer forwards NNAPI configuration.
- Local manifests and build files isolate the minimal ML interfaces from the
  rest of the Stripe SDK.

## CardScan module

- `cardscan/CardScanActivity.kt`: removes analytics and Dagger setup; adds the
  CardVault result contract, bounded gallery import, accepted-frame persistence,
  20-second timeout, lifecycle cleanup, and CardVault scan-state UI.
- `cardscan/CardScanFlow.kt`: waits for in-flight native inference before
  closing interpreters, preventing teardown races and native crashes.
- `cardscan/result/MainLoopAggregator.kt`: requires repeated Luhn-valid PAN
  agreement, retains only the sharpest matching preview crop, and recycles all
  rejected bitmaps.
- `payment/ml/SSDOcr.kt`: exposes one bounded accepted-frame candidate, supports
  centered gallery crops, and uses only the CPU interpreter configuration.
- `src/main/AndroidManifest.xml`: exposes only the local scan activity and
  camera capability needed by CardVault; no network permission is declared.
- `src/androidTest/.../LiteRtModelSmokeTest.kt`: verifies that the bundled model
  opens and performs an inference with the pinned runtime.

## Review disposition

Prefer upstream fixes for camera, lifecycle, image safety, and ML behavior.
CardVault-only product behavior (result bridge, offline-only dependency surface,
gallery workflow, and UI) remains isolated here. Each upstream review must
confirm this inventory against a clean checkout of the pinned and candidate
commits and update the provenance review date even when no code is changed.
