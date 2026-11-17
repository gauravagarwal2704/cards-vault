# Release APK Build Information

## Build Status: ✅ SUCCESS

### Release Artifacts

#### APK (Direct Installation)
- **Location**: `build/app/outputs/flutter-apk/app-release.apk`
- **Size**: 59 MB (62.4 MB)
- **Use Case**: Direct installation on devices, testing, distribution outside Play Store

#### App Bundle (Play Store)
- **Location**: `build/app/outputs/bundle/release/app-release.aab`
- **Size**: 28 MB (29.3 MB)
- **Use Case**: Google Play Store distribution (recommended)
- **Benefit**: ~52% smaller than APK, dynamic delivery

#### Common Details
- **Build Date**: January 29, 2026
- **Application ID**: com.cardswallet.cards_wallet
- **Version**: 1.0.0+1

### Build Configuration

#### Signing Configuration
- **Keystore**: `android/app/upload-keystore.jks`
- **Key Alias**: upload
- **Validity**: 10,000 days
- **Key Algorithm**: RSA 2048-bit
- **Note**: Keystore credentials are stored in `android/key.properties` (excluded from git)

#### Build Settings
- **Min SDK**: 26 (Android 8.0)
- **Target SDK**: 34 (Android 14)
- **Compile SDK**: 34
- **NDK Version**: 25.1.8937393
- **ABI Filters**: arm64-v8a (64-bit ARM only)
- **Minify Enabled**: Yes (R8)
- **Shrink Resources**: Yes

#### Optimizations Applied
- ProGuard/R8 code minification
- Resource shrinking
- Tree-shaking (MaterialIcons reduced by 99.6%)
- Native library filtering (arm64-v8a only)

### Issues Fixed

1. **Missing Signing Configuration**
   - Created upload keystore for release signing
   - Configured signing in build.gradle

2. **NDK Version Mismatch**
   - Updated to NDK version 25.1.8937393

3. **R8 Minification Errors**
   - Added ProGuard rules for:
     - Google ML Kit language-specific text recognizers
     - TensorFlow Lite GPU delegates
     - Play Core deferred components
     - Flutter core classes

### Security Notes

⚠️ **Important**: The following files contain sensitive information and are excluded from version control:
- `android/app/upload-keystore.jks`
- `android/key.properties`

**For production release**, you should:
1. Generate a new keystore with strong passwords
2. Store keystore securely (not in repository)
3. Update key.properties with production credentials
4. Consider using Play App Signing for additional security

### Installation

To install the APK on a device:
```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

Or transfer the APK file to your device and install it manually.

### Building Again

To rebuild the release APK:
```bash
flutter build apk --release
```

To build an app bundle (recommended for Play Store):
```bash
flutter build appbundle --release
```

### App Bundle vs APK

| Feature | APK | App Bundle |
|---------|-----|------------|
| Size | 59 MB | 28 MB (52% smaller) |
| Distribution | Direct install, third-party stores | Google Play Store |
| Optimization | Single APK for all devices | Dynamic delivery per device |
| Recommended For | Testing, sideloading | Play Store release |

**Play Store Distribution**: The app bundle (`.aab`) is the recommended format for Google Play Store as it allows Google to optimize the download size for each device configuration.
