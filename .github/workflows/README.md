# Automated Android releases

This directory intentionally contains documentation only. Add the workflow
described below when CardVault is ready to publish signed, ABI-specific APKs to
GitHub Releases automatically.

## What the future workflow should do

When a version tag such as `v1.2.2` is pushed, the workflow should:

1. Check out the tagged commit.
2. Install Java 17 and Flutter 3.47.0.
3. Restore the Android release keystore from encrypted GitHub secrets.
4. Run `flutter analyze` and `flutter test`.
5. Run `flutter build apk --release --split-per-abi`.
6. Rename the generated APKs so their ABI is clear.
7. Generate SHA-256 checksums.
8. Create a GitHub Release and attach all three APKs and the checksum file.

The generated APKs are expected at:

```text
build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk
build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
build/app/outputs/flutter-apk/app-x86_64-release.apk
```

Keep `/build/` in `.gitignore`. GitHub Actions can upload generated files
without committing them to the repository.

## Required GitHub secrets

Before enabling the workflow, add these encrypted repository secrets under
**Settings > Secrets and variables > Actions**:

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`

On macOS, copy the Base64-encoded keystore value with:

```bash
base64 -i /path/to/upload-keystore.jks | pbcopy
```

Never commit the keystore or `android/key.properties`.

## Workflow template

When automation is ready to be enabled, save the following as
`.github/workflows/android-release.yml`:

```yaml
name: Android GitHub Release

on:
  push:
    tags:
      - "v*"

permissions:
  contents: write

concurrency:
  group: android-release-${{ github.ref }}
  cancel-in-progress: false

jobs:
  build-and-release:
    name: Build signed APKs and publish release
    runs-on: ubuntu-latest
    timeout-minutes: 45

    steps:
      - name: Check out release tag
        uses: actions/checkout@v4

      - name: Set up Java
        uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: "17"

      - name: Set up Flutter
        uses: subosito/flutter-action@v2
        with:
          flutter-version: "3.47.0"
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze

      - name: Test
        run: flutter test

      - name: Restore Android release signing
        shell: bash
        env:
          KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          STORE_PASSWORD: ${{ secrets.ANDROID_STORE_PASSWORD }}
          KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}
          KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
        run: |
          test -n "$KEYSTORE_BASE64"
          test -n "$STORE_PASSWORD"
          test -n "$KEY_PASSWORD"
          test -n "$KEY_ALIAS"

          printf '%s' "$KEYSTORE_BASE64" | base64 --decode > android/app/upload-keystore.jks
          printf '%s\n' \
            "storePassword=$STORE_PASSWORD" \
            "keyPassword=$KEY_PASSWORD" \
            "keyAlias=$KEY_ALIAS" \
            "storeFile=upload-keystore.jks" \
            > android/key.properties

      - name: Build ABI-specific release APKs
        run: flutter build apk --release --split-per-abi

      - name: Prepare release assets
        shell: bash
        run: |
          version="${GITHUB_REF_NAME#v}"
          mkdir -p dist
          cp build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "dist/cardvault-${version}-armeabi-v7a.apk"
          cp build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "dist/cardvault-${version}-arm64-v8a.apk"
          cp build/app/outputs/flutter-apk/app-x86_64-release.apk "dist/cardvault-${version}-x86_64.apk"
          cd dist
          sha256sum ./*.apk > SHA256SUMS.txt

      - name: Publish GitHub release
        shell: bash
        env:
          GH_TOKEN: ${{ github.token }}
        run: |
          gh release create "$GITHUB_REF_NAME" \
            dist/*.apk \
            dist/SHA256SUMS.txt \
            --verify-tag \
            --title "CardVault ${GITHUB_REF_NAME#v}" \
            --generate-notes
```

## Enabling it later

1. Add the four repository secrets.
2. Copy the template into `android-release.yml` in this directory.
3. Commit and merge the workflow into the default branch.
4. Increase the version and build number in `pubspec.yaml`.
5. Create and push a new tag only after the workflow exists on the default
   branch:

   ```bash
   git tag -a v1.2.2 -m "CardVault 1.2.2"
   git push origin v1.2.2
   ```

For Google Play, continue uploading an Android App Bundle (`.aab`). The
ABI-specific APKs are intended for direct GitHub downloads.
