# Dependency maintenance policy

CardVault pins direct Dart and native Android dependencies to reviewed versions.
`pubspec.lock` is committed and must change in the same pull request as a
dependency constraint. Dependabot opens Pub and Gradle updates every Monday in
the Asia/Kolkata maintenance window; security alerts and security update pull
requests should be enabled in the repository settings and handled immediately.

Do not auto-merge dependency updates. For every update:

1. Read the complete upstream changelog, migration guide, and security advisory
   history from the currently pinned version through the proposed version.
2. Confirm the package source, maintainer, license, release provenance, and
   checksum resolved in the lockfile. Review the full `pubspec.lock` or Gradle
   dependency diff for new transitive packages, permissions, telemetry,
   network access, native libraries, and platform deployment changes.
3. Give manual security review to storage, authentication, cryptography,
   backup/archive, NFC, camera/OCR, file-picker, and vendored scanner changes.
   Major upgrades remain separate pull requests so their migration risk is not
   hidden inside the grouped minor/patch update.
4. Run `flutter pub get`, `flutter pub deps --style=compact`, `flutter analyze`,
   and the full `flutter test` suite. Add focused regression tests for behavior
   changed by the dependency.
5. Build `flutter build apk --release --split-per-abi`; inspect the merged
   Android manifest and APK contents when a plugin or native dependency changes.
   Run the scanner AAR build and physical scan smoke suite for camera, LiteRT,
   OCR, or CardScan changes.
6. Record the changelog risks reviewed, test/build evidence, APK size delta,
   and rollback version in the pull request before approval.

Emergency security updates bypass the weekly batching window, but they do not
bypass review, tests, the Android release build, or rollback planning.
