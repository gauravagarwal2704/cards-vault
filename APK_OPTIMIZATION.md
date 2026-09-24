# APK Optimization Summary

## Problem
Debug APK was **560MB**, causing slow installation times when running `flutter run` or `adb install`.

## Root Causes
1. **Vulkan Validation Layer (248MB)**: Debug-only library `libVkLayer_khronos_validation.so` for graphics debugging
2. **Multiple ABIs (4x size)**: Building for arm64-v8a, armeabi-v7a, x86, and x86_64
3. **Unoptimized Debug Code (71MB)**: Large kernel_blob.bin

## Solution Applied

### 1. Single ABI for Debug Builds
Modified `android/app/build.gradle` to only build for arm64-v8a (most modern devices):

```gradle
defaultConfig {
    ...
    ndk {
        abiFilters 'arm64-v8a'
    }
}
```

### 2. Exclude Vulkan Validation Layer
Added packaging options to exclude the large debug library:

```gradle
buildTypes {
    debug {
        minifyEnabled false
        shrinkResources false
        
        packagingOptions {
            jniLibs {
                excludes += ['**/libVkLayer_khronos_validation.so']
            }
        }
    }
    ...
}
```

## Results
- **Before**: 560MB
- **After**: 112MB
- **Reduction**: 80% (448MB saved)
- **Installation time**: Significantly faster

## Native Libraries in Optimized APK
- libflutter.so: 37.8MB
- libdigitalink.so: 10.8MB
- libtesseract.so: 4.7MB
- libleptonica.so: 2.7MB
- libjpeg.so: 0.2MB
- libpngx.so: 0.2MB

The card scanner no longer packages ML Kit, Google Play Services, or
TensorFlow Lite. Verify current size from a fresh release APK rather than the
historical totals above.

## Notes
- Release builds remain unaffected
- If testing on older devices (32-bit), temporarily add 'armeabi-v7a' to abiFilters
- For x86 emulators, add 'x86_64' to abiFilters
- Most modern Android devices (2017+) use arm64-v8a
