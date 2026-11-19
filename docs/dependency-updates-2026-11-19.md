# Dependency review — 19 November 2026

This branch consolidates all five open Dependabot PRs: [#19](https://github.com/gauravagarwal2704/cards-vault/pull/19), [#14](https://github.com/gauravagarwal2704/cards-vault/pull/14), [#5](https://github.com/gauravagarwal2704/cards-vault/pull/5), [#4](https://github.com/gauravagarwal2704/cards-vault/pull/4), and [#3](https://github.com/gauravagarwal2704/cards-vault/pull/3). The requested one-PR approach is a one-off grouping of the three major plugin migrations with the grouped updates; it does not change the normal [dependency maintenance policy](dependency-maintenance.md).

## Reviewed versions and migrations

| Dependency | Previous | Proposed | Review / integration |
| --- | --- | --- | --- |
| camera | 0.10.6 | 0.12.2 | Switches the endorsed Android backend from `camera_android` to `camera_android_camerax`; iOS backend also updates. CardVault's Android scan screen still uses its isolated native scanner. Lifecycle tests and real-device scanning are required. |
| crypto | 3.0.7 | 3.0.8 | Fixes completion of chunked HMAC conversion and updates hashing internals. Backup and encryption regression coverage remains required; encryption format and KDF parameters are unchanged. |
| flutter_nfc_kit | 3.6.2 | 3.7.0 | Fixes stale iOS session invalidation and adopts Flutter's AGP 9 Kotlin compatibility path. Requires Flutter 3.47+; the current toolchain satisfies this. |
| flutter_svg | 2.3.0 | 2.4.0 | Adds bounded compiled-cache accounting and fixes failed/pending-load handling. Card/network-logo and widget-artwork coverage exercises SVG rendering. |
| image_picker | 1.2.3 | 1.2.4 | Clarifies one-time lost-data retrieval and raises the minimum Flutter version within the app's existing SDK range. |
| shared_preferences | 2.5.5 | 2.5.6 | Documents setter/removal return behavior; review covered preference and app-lock tests. |
| url_launcher | 6.3.2 | 6.3.3 | Corrects support detection for closing launch modes; external support links remain user initiated. |
| file_picker | 10.3.10 | 11.0.3 | Breaking static API migration. Updated backup picking and diagnostic saving; diagnostic export retains injectable callbacks, cancellation handling, and redaction tests. Added a `file_picker`-only KGP compatibility hook because its AGP 9 conditional suppresses Kotlin compilation while this project opts out of built-in Kotlin. Includes upstream path-traversal hardening and removes Apache Tika. |
| image_cropper | 11.0.0 | 12.2.1 | iOS TOCropViewController/UIScene and aspect-ratio fixes; Android release-build fix. Existing Dart crop settings remain compatible. Its TOCropViewController 3.x requirement conflicts with file_picker 11’s unused SwiftPM media picker (TOCropViewController 2.x). The project uses the supported CocoaPods document-only picker flags instead; file_picker media/audio support is excluded, while image_picker continues to handle photographs. The unsigned iOS device debug build also passes after the CocoaPods document-only configuration and native lockfile refresh. |
| package_info_plus | 8.3.1 | 9.0.1 | Android build/compile SDK update; the `PackageInfo.fromPlatform` API used by Settings and support remains compatible. |
| Android Gradle Plugin (app/library and compatibility override) | 9.1.0 | 9.5.0 | Updated both declarations and the plugin-classpath compatibility override; leaving the latter stale would force plugins back to 9.1.0. |
| Kotlin Gradle Plugin | 2.4.0 | 2.4.21 | Addresses the known build-cache deserialization advisory listed below. Flutter's existing legacy-KGP compatibility path is retained for plugins still requiring it. |
| Gradle wrapper | 9.3.1 | 9.8.2 | Added the official distribution SHA-256 and verified the downloaded ZIP against it. Uses Java 17 for the Android build. |
| AndroidX Annotation | 1.9.1 | 1.11.0 | Updated across the local scanner modules. |
| AndroidX AppCompat | 1.7.0 | 1.8.0 | Updated in camera and CardScan modules; UI/device checks remain part of scanner validation. |
| AndroidX ConstraintLayout | 2.2.0 | 2.2.2 | Updated the native scanner layout dependency. |
| AndroidX Core KTX | 1.13.1 | 1.19.1 | Its AAR declares `minCompileSdk=37`; raised app, scanner-module, and plugin compile settings to 37. Minimum API remains 26 and target SDK remains Flutter's existing value. |
| kotlinx-coroutines-android | 1.10.1 | 1.11.0 | Review covers analyzer cancellation, lifecycle cleanup, and interpreter disposal. |
| LiteRT | 2.2.0 | 2.3.2 | Keeps the CPU Interpreter API, original bundled model, optional-GPU exclusion, and offline operation. Fork revision becomes 2; the pinned Stripe source commit is unchanged. Strengthened the instrumented model smoke test to perform inference and verify both output tensors. |

## Source, license, and advisory review

Pub packages continue to resolve from `https://pub.dev`. All 12 changed package archives (10 direct dependencies plus the CameraX/AVFoundation backend changes) were checked against the hashes reported by Pub.dev's version API. The committed lockfile retains those SHA-256 values. CameraX replaces the previous Android camera backend; no unrelated Dart package was added. The iOS integration uses project-scoped CocoaPods configuration because file_picker’s SwiftPM manifest cannot disable its unused media dependency. Existing package maintainers/repository identities and bundled license notices were reviewed, with no change to CardVault's use of Flutter/Dart BSD-licensed packages or the plugins' MIT/Apache-style license notices. The scanner model, Stripe source baseline, and existing notices are unchanged.

OSV queries covered 23 old/new Pub package versions and 16 old/new Maven versions. They reported no matches for the proposed versions in that queried set, and identified [GHSA-r937-wjx7-w2jp / CVE-2026-53914](https://github.com/advisories/GHSA-r937-wjx7-w2jp) in the old Kotlin Gradle plugin. Kotlin 2.4.21 is beyond its patched threshold. Database results are not a guarantee against unreported issues: file_picker's own changelog separately documents the path-traversal fix in 11.0.2.

The [Gradle 9.8.2 release notes](https://docs.gradle.org/9.8.2/release-notes.html) also identify security fixes shipped in the 9.8 line. The wrapper is downloaded over verified TLS and pinned to the official distribution checksum. Local Java download checks used a task-local trust store containing the environment's pre-existing CAs; TLS validation was not disabled and no machine-wide certificate settings were changed.

Primary references reviewed:

- The complete intervening changelog sections bundled in the selected Pub package archives; [file_picker 11.0.3](https://pub.dev/packages/file_picker/versions/11.0.3/changelog), [image_cropper 12.2.1](https://pub.dev/packages/image_cropper/versions/12.2.1/changelog), [package_info_plus 9.0.1](https://pub.dev/packages/package_info_plus/versions/9.0.1/changelog), and the repositories recorded in each package's pubspec.
- [AGP 9.5 compatibility](https://developer.android.com/build/releases/agp-9-5-0-release-notes), [Kotlin 2.4.21](https://github.com/JetBrains/kotlin/releases/tag/v2.4.21), [Flutter Kotlin compatibility/migration](https://docs.flutter.dev/release/breaking-changes/migrate-to-built-in-kotlin/for-app-developers).
- [AndroidX Annotation](https://developer.android.com/jetpack/androidx/releases/annotation), [AppCompat](https://developer.android.com/jetpack/androidx/releases/appcompat), [ConstraintLayout](https://developer.android.com/jetpack/androidx/releases/constraintlayout), [Core](https://developer.android.com/jetpack/androidx/releases/core), [coroutines](https://github.com/Kotlin/kotlinx.coroutines/releases/tag/1.11.0), and [LiteRT 2.3.2](https://github.com/google-ai-edge/LiteRT/releases/tag/v2.3.2).

## Validation and release gates

- Final Dart static analysis and all 230 Flutter tests pass after the API, storage-permission, and project configuration changes. The 13 focused dependency/release/scanner tests also pass.
- Native unit tests (9), scanner AAR/instrumentation compilation, and both scanner instrumentation tests pass on an arm64 Android 14 emulator. The model test performs actual inference; the lifecycle test reuses and releases image buffers. The signed APK build passes. The final APK permission set exactly matches 1.14.0. The unsigned iOS device debug build also passes after the CocoaPods document-only configuration and native lockfile refresh.
- Production inspection caught newly merged `READ_EXTERNAL_STORAGE` and `WRITE_EXTERNAL_STORAGE` permissions. The application explicitly removes both because backup/photo selection uses scoped pickers. A regression check preserves those removals. The APKs must retain the original permission set, API 26 minimum, API 36 target, valid signing certificate, unchanged bundled model, and scanner payload below 5 MiB.
- The iOS CocoaPods lockfile is refreshed and stale SwiftPM resolution files are removed. The unsigned iOS device debug build passes. CocoaPods ran from a temporary Ruby-4-compatible gem directory because the machine’s global `pod` executable points at obsolete Ruby 3.4 gems; no global gems were changed.
- An isolated read-only Android emulator is used for automated scanner instrumentation. This cannot establish real camera quality, physical NFC compatibility, or physical-device lifecycle behavior.
- **Keep the PR as a draft until the physical arm64 scanner/NFC smoke suite is completed and reviewed.** Exercise live/gallery scan, permission denial, cancellation, timeout, repeated open/close, and background/resume. No physical device was connected during validation.

## Android release inspection

Signed split-ABI APKs retain API 26 minimum / API 36 target while compiling
against API 37. Signing certificates match 1.14.0; there are no new production
permissions or native-library filenames, and the bundled model hash is unchanged.
No Internet, microphone, broad external-storage, or model-delivery foreground
service permission is packaged. The optional LiteRT GPU accelerator is absent.

| ABI | 1.14.0 bytes | 1.14.1 bytes | Delta | Compressed scanner bytes |
| --- | ---: | ---: | ---: | ---: |
| armeabi-v7a | 27,891,578 | 27,813,085 | -78,493 | 3,746,467 |
| arm64-v8a | 28,874,922 | 28,819,141 | -55,781 | 4,212,318 |
| x86_64 | 30,113,918 | 30,062,601 | -51,317 | 5,001,576 |

All three scanner payloads pass the existing 5 MiB budget.

## Rollback

The pre-update dependency set is in main at `7c8d1703ebd380d6408d6ea2f5caa764f815fdd5` (app 1.14.0+47). Revert the dependency pins, lockfile, SDK/build-tool changes, and file-picker API migration together; reverting only the pubspec would leave incompatible calls. Preserve existing release history. If a released build needs a rollback, publish a new patch/build number rather than reusing or lowering the installed version code. Do not change stored-card encryption or backup formats during rollback.
