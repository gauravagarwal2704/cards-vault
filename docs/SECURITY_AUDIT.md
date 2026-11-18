# Security Audit Report - Cards Wallet NFC App

**Date**: December 31, 2025  
**Project**: Cards Wallet - NFC Credit Card Reader  
**Overall Risk Level**: 🔴 **CRITICAL**  
**Status**: ⚠️ **NOT PRODUCTION READY**

---

## Executive Summary

This security audit identified **12 significant security vulnerabilities** in the Cards Wallet NFC application. The most critical issues involve **unencrypted storage and transmission of payment card data** and **extensive debug logging of sensitive information**. The application currently violates PCI DSS compliance requirements and poses significant risks to user financial data.

**Critical Issues**: 2  
**High Priority Issues**: 3  
**Medium Priority Issues**: 6  
**Low Priority Issues**: 1

---

## 🔴 CRITICAL SECURITY ISSUES

### 1. NO ENCRYPTION OF SENSITIVE CARD DATA

**Severity**: 🔴 CRITICAL  
**Status**: ❌ UNRESOLVED  
**PCI DSS Violation**: Requirement 3.4

**Description**:
Payment card data (PAN, expiry date, cardholder name) is read from NFC chips and handled in **PLAIN TEXT** throughout the application. No encryption is applied during processing, storage, or potential transmission.

**Affected Files**:
- `lib/services/nfc_service.dart` (lines 619-621, 659-660, 669-670, 690-691, 703-704)
- `lib/models/card_data.dart` (entire class)
- `lib/providers/nfc_provider.dart` (line 52)

**Evidence**:
```dart
// TODO: ENCRYPT THIS DATA IMMEDIATELY
// Card data is currently in plain text and must be encrypted before storage or transmission
// Consider using flutter_secure_storage or similar encryption mechanism
```

**Risk**:
- Complete payment card information exposed if intercepted
- Data vulnerable to memory dumps
- Non-compliance with PCI DSS standards
- Potential for financial fraud

**Remediation**:
1. Implement end-to-end encryption using `flutter_secure_storage` package
2. Encrypt card data immediately after reading from NFC
3. Use AES-256 encryption for data at rest
4. Implement secure key management (Android Keystore/iOS Keychain)
5. Never store unencrypted card data in memory longer than necessary
6. Consider tokenization for stored card references

**Recommended Packages**:
- `flutter_secure_storage: ^9.0.0`
- `encrypt: ^5.0.3`
- `cryptography: ^2.7.0`

---

### 2. EXTENSIVE DEBUG LOGGING OF SENSITIVE DATA

**Severity**: 🔴 CRITICAL  
**Status**: ❌ UNRESOLVED  
**PCI DSS Violation**: Requirement 10.2

**Description**:
Full payment card data is being logged to console and system logs using `print()` and `developer.log()`. This creates a persistent record of sensitive information accessible to other applications and debugging tools.

**Affected Files**:
- `lib/utils/debug_logger.dart` (lines 4-11)
- `lib/services/nfc_service.dart` (60+ instances of DebugLogger.log calls)
- `lib/services/nfc_service.dart` (lines 124-125 - error logging)

**Evidence**:
```dart
// debug_logger.dart
print('[NFC_DEBUG] $location: $message | Data: $data');

// nfc_service.dart
DebugLogger.log('nfc_service.dart:237', 'Card data extracted successfully', 
    {'hasPAN': pan != null, 'hasExpiry': expiryDate != null, 'hasName': cardholderName != null}, 'H6');

print('[NFC_ERROR] Final error: ${e.toString()}');
```

**Risk**:
- Card data persists in device logs
- Accessible via ADB (Android Debug Bridge)
- Can be extracted by malware or other apps with log access
- Violates PCI DSS logging requirements
- Privacy violation (GDPR/CCPA)

**Remediation**:
1. **IMMEDIATE**: Disable all debug logging in production builds
2. Implement conditional logging based on build mode:
```dart
static void log(String location, String message, Map<String, dynamic> data, String hypothesisId) {
  if (kDebugMode) {
    // Only log in debug mode, and sanitize sensitive data
    developer.log(
      '$message | Data: ${_sanitizeData(data)}',
      name: 'NFC_DEBUG',
      time: DateTime.now(),
    );
  }
}
```
3. Create a data sanitization function that masks PAN/expiry
4. Remove all `print()` statements containing sensitive data
5. Use proper error reporting services (Firebase Crashlytics) with data sanitization

---

## 🟠 HIGH PRIORITY ISSUES

### 3. NO DATA STORAGE SECURITY

**Severity**: 🟠 HIGH  
**Status**: ❌ UNRESOLVED

**Description**:
The application has a "Save Card" button but no secure storage mechanism is implemented. If card data is persisted, it would be stored without encryption.

**Affected Files**:
- `lib/screens/add_card_screen.dart` (lines 547-571)
- `pubspec.yaml` (missing secure storage dependencies)

**Evidence**:
```dart
ElevatedButton(
  onPressed: () {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Card saved successfully!'),
        backgroundColor: Colors.green,
      ),
    );
  },
  child: const Text('Save Card'),
)
```

**Risk**:
- Future implementation may store cards insecurely
- Data accessible to anyone with device access
- Vulnerable to device backup extraction
- Non-compliance with PCI DSS Requirement 3.4

**Remediation**:
1. Add `flutter_secure_storage` dependency
2. Implement encrypted storage service:
```dart
class SecureCardStorage {
  final FlutterSecureStorage _storage = FlutterSecureStorage();
  
  Future<void> saveCard(CardData card) async {
    // Encrypt and store card data
    final encryptedData = await _encryptCardData(card);
    await _storage.write(key: 'card_${card.cardNumber.substring(12)}', value: encryptedData);
  }
}
```
3. Never use SharedPreferences for card data
4. Implement data expiration/auto-deletion
5. Add biometric authentication before accessing stored cards

---

### 4. CARD DATA DISPLAYED IN PLAIN TEXT IN UI

**Severity**: 🟠 HIGH  
**Status**: ❌ UNRESOLVED  
**PCI DSS Violation**: Requirement 3.3 (Partial)

**Description**:
Full unmasked card numbers are displayed in the user interface, making them vulnerable to shoulder surfing, screenshots, screen recordings, and accessibility services.

**Affected Files**:
- `lib/screens/add_card_screen.dart` (lines 275-282, 399)
- `lib/models/card_data.dart` (line 14-19)

**Evidence**:
```dart
Text(
  cardData.formattedCardNumber,  // Shows full card number: "1234 5678 9012 3456"
  style: const TextStyle(
    color: Colors.white,
    fontSize: 22,
    fontWeight: FontWeight.w500,
    letterSpacing: 2,
  ),
),
```

**Risk**:
- Shoulder surfing attacks
- Screenshot/screen recording capture
- Accessibility service data extraction
- Malicious overlays can capture displayed data
- Social engineering attacks using photos

**Remediation**:
1. Display only masked card numbers by default (show last 4 digits)
2. Implement "tap to reveal" with biometric authentication
3. Use `maskedCardNumber` property instead of `formattedCardNumber`
4. Add screenshot prevention:
```dart
// Android: Add to MainActivity
window.setFlags(WindowManager.LayoutParams.FLAG_SECURE, WindowManager.LayoutParams.FLAG_SECURE);
```
5. Implement auto-hide after timeout
6. Add blur effect when app goes to background

---

### 5. RELEASE BUILD SIGNED WITH DEBUG KEYS

**Severity**: 🟠 HIGH  
**Status**: ❌ UNRESOLVED

**Description**:
The Android release build configuration uses debug signing keys, which are publicly known and not secure.

**Affected Files**:
- `android/app/build.gradle` (lines 51-56)

**Evidence**:
```gradle
buildTypes {
    release {
        // TODO: Add your own signing config for the release build.
        // Signing with the debug keys for now, so `flutter run --release` works.
        signingConfig = signingConfigs.debug
    }
}
```

**Risk**:
- Anyone can re-sign and distribute modified versions of the app
- No authenticity guarantee for users
- App store rejection
- Malware distribution using same signature
- Cannot be published to Google Play Store

**Remediation**:
1. Generate production keystore:
```bash
keytool -genkey -v -keystore ~/cards-wallet-release.keystore -alias cards-wallet -keyalg RSA -keysize 2048 -validity 10000
```
2. Create `android/key.properties`:
```properties
storePassword=<password>
keyPassword=<password>
keyAlias=cards-wallet
storeFile=<path-to-keystore>
```
3. Update `build.gradle`:
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile keystoreProperties['storeFile'] ? file(keystoreProperties['storeFile']) : null
            storePassword keystoreProperties['storePassword']
        }
    }
    buildTypes {
        release {
            signingConfig signingConfigs.release
            minifyEnabled true
            shrinkResources true
        }
    }
}
```
4. Add `key.properties` to `.gitignore`
5. Store keystore securely (not in repository)

---

## 🟡 MEDIUM PRIORITY ISSUES

### 6. NO CERTIFICATE PINNING OR NETWORK SECURITY

**Severity**: 🟡 MEDIUM  
**Status**: ❌ UNRESOLVED

**Description**:
No network security configuration is present. If future versions add API calls for card validation or processing, they would be vulnerable to man-in-the-middle attacks.

**Affected Files**:
- `android/app/src/main/res/xml/network_security_config.xml` (missing)
- `android/app/src/main/AndroidManifest.xml` (no networkSecurityConfig attribute)

**Risk**:
- MITM attacks on future API calls
- SSL stripping attacks
- Data interception during transmission
- Certificate spoofing

**Remediation**:
1. Create `android/app/src/main/res/xml/network_security_config.xml`:
```xml
<?xml version="1.0" encoding="utf-8"?>
<network-security-config>
    <base-config cleartextTrafficPermitted="false">
        <trust-anchors>
            <certificates src="system" />
        </trust-anchors>
    </base-config>
    <domain-config cleartextTrafficPermitted="false">
        <domain includeSubdomains="true">your-api-domain.com</domain>
        <pin-set expiration="2026-12-31">
            <pin digest="SHA-256">base64-encoded-pin-here</pin>
            <pin digest="SHA-256">backup-pin-here</pin>
        </pin-set>
    </domain-config>
</network-security-config>
```
2. Update AndroidManifest.xml:
```xml
<application
    android:networkSecurityConfig="@xml/network_security_config"
    ...>
```
3. Implement certificate pinning in Dart using `http` package with `SecurityContext`
4. Use HTTPS only for all network communications

---

### 7. INSUFFICIENT INPUT VALIDATION

**Severity**: 🟡 MEDIUM  
**Status**: ❌ UNRESOLVED

**Description**:
Limited validation of NFC data parsed from cards. Malformed or malicious NFC tags could cause crashes or unexpected behavior.

**Affected Files**:
- `lib/utils/hex_utils.dart` (lines 6-18, 41-51)
- `lib/services/apdu_commands.dart` (TLVParser class)
- `lib/services/nfc_service.dart` (data extraction methods)

**Risk**:
- Application crashes from malformed data
- Potential buffer overflow vulnerabilities
- Denial of service attacks
- Unexpected behavior from crafted NFC tags

**Remediation**:
1. Add comprehensive input validation:
```dart
static List<int> hexToBytes(String hex) {
  hex = hex.replaceAll(' ', '');
  
  // Validate hex string
  if (!RegExp(r'^[0-9A-Fa-f]*$').hasMatch(hex)) {
    throw FormatException('Invalid hex string: contains non-hex characters');
  }
  
  if (hex.length % 2 != 0) {
    throw FormatException('Hex string must have an even length');
  }
  
  if (hex.length > 1024) { // Reasonable limit
    throw FormatException('Hex string too long');
  }
  
  List<int> bytes = [];
  for (int i = 0; i < hex.length; i += 2) {
    String hexByte = hex.substring(i, i + 2);
    bytes.add(int.parse(hexByte, radix: 16));
  }
  return bytes;
}
```
2. Validate PAN format (Luhn algorithm)
3. Validate expiry date ranges
4. Add length checks for all parsed fields
5. Implement try-catch with specific error handling

---

### 8. NO OBFUSCATION OR CODE PROTECTION

**Severity**: 🟡 MEDIUM  
**Status**: ❌ UNRESOLVED

**Description**:
No code obfuscation is enabled, making it easy to reverse engineer the application and understand the NFC reading logic.

**Affected Files**:
- `android/app/build.gradle` (missing ProGuard/R8 configuration)
- Build configuration (missing Dart obfuscation flags)

**Risk**:
- Easy reverse engineering
- Intellectual property theft
- Security mechanism discovery
- Easier to find vulnerabilities
- Cloning of NFC reading logic

**Remediation**:
1. Enable R8/ProGuard for Android:
```gradle
buildTypes {
    release {
        minifyEnabled true
        shrinkResources true
        proguardFiles getDefaultProguardFile('proguard-android-optimize.txt'), 'proguard-rules.pro'
    }
}
```
2. Create `android/app/proguard-rules.pro`:
```proguard
-keep class com.cardswallet.cards_wallet.** { *; }
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**
```
3. Build with Dart obfuscation:
```bash
flutter build apk --obfuscate --split-debug-info=build/debug-info
flutter build appbundle --obfuscate --split-debug-info=build/debug-info
```
4. Add to `.gitignore`:
```
build/debug-info/
```
5. Store symbol maps securely for crash analysis

---

### 9. MISSING SECURITY PERMISSIONS AND CONFIGURATIONS

**Severity**: 🟡 MEDIUM  
**Status**: ❌ UNRESOLVED

**Description**:
Several security-related configurations are missing from Android and iOS manifests.

**Affected Files**:
- `android/app/src/main/AndroidManifest.xml`
- `ios/Runner/Info.plist`

**Issues**:
- No `android:allowBackup="false"` (allows backup of app data)
- No `android:usesCleartextTraffic="false"` (allows HTTP traffic)
- Missing iOS NFC usage descriptions for production

**Risk**:
- Sensitive data backed up to cloud services
- Data extraction via ADB backup
- Cleartext traffic allowed by default
- App store rejection (iOS)

**Remediation**:
1. Update AndroidManifest.xml:
```xml
<application
    android:allowBackup="false"
    android:usesCleartextTraffic="false"
    android:networkSecurityConfig="@xml/network_security_config"
    android:label="cards_wallet"
    android:name="${applicationName}"
    android:icon="@mipmap/ic_launcher">
```
2. Add to Info.plist (iOS):
```xml
<key>NFCReaderUsageDescription</key>
<string>This app needs NFC access to read payment card information securely.</string>
<key>com.apple.developer.nfc.readersession.formats</key>
<array>
    <string>TAG</string>
</array>
```
3. Add iOS entitlements for NFC
4. Disable screenshots in sensitive screens

---

### 10. NO RUNTIME SECURITY CHECKS

**Severity**: 🟡 MEDIUM  
**Status**: ❌ UNRESOLVED

**Description**:
The application lacks runtime security checks for compromised environments (rooted/jailbroken devices, debuggers, emulators).

**Affected Files**:
- None (feature missing entirely)

**Risk**:
- App runs on compromised devices
- Easier data extraction on rooted devices
- Debugger attachment for runtime analysis
- Emulator testing for reverse engineering

**Remediation**:
1. Add security packages:
```yaml
dependencies:
  flutter_jailbreak_detection: ^1.10.0
  safe_device: ^1.1.5
```
2. Implement security checks:
```dart
class SecurityService {
  Future<bool> isDeviceSecure() async {
    bool isJailbroken = await FlutterJailbreakDetection.jailbroken;
    bool isDevelopmentMode = await FlutterJailbreakDetection.developerMode;
    
    if (isJailbroken || isDevelopmentMode) {
      return false;
    }
    return true;
  }
  
  Future<void> checkSecurityOnStartup() async {
    if (!await isDeviceSecure()) {
      // Show warning or disable sensitive features
      throw SecurityException('Device is not secure');
    }
  }
}
```
3. Implement debugger detection
4. Add emulator detection
5. Consider disabling app on compromised devices

---

### 11. CARDDATA MODEL EXPOSES FULL PAN

**Severity**: 🟡 MEDIUM  
**Status**: ❌ UNRESOLVED

**Description**:
The CardData model's `toString()` method uses masked card number, but the full PAN is still directly accessible via the `cardNumber` property, risking accidental logging.

**Affected Files**:
- `lib/models/card_data.dart` (lines 1-32)

**Evidence**:
```dart
class CardData {
  final String cardNumber;  // Full PAN directly accessible
  
  @override
  String toString() {
    return 'CardData(cardNumber: $maskedCardNumber, expiryDate: $expiryDate, cardType: $cardType)';
  }
}
```

**Risk**:
- Accidental logging of full PAN
- Easy to mistakenly expose in error messages
- Serialization may expose full number

**Remediation**:
1. Make `cardNumber` private and provide controlled access:
```dart
class CardData {
  final String _cardNumber;
  final String expiryDate;
  final String? cardholderName;
  final String cardType;

  CardData({
    required String cardNumber,
    required this.expiryDate,
    this.cardholderName,
    required this.cardType,
  }) : _cardNumber = cardNumber;

  String get lastFourDigits => _cardNumber.substring(_cardNumber.length - 4);
  
  String getFullCardNumber({required bool authenticated}) {
    if (!authenticated) {
      throw SecurityException('Authentication required to access full card number');
    }
    return _cardNumber;
  }

  String get formattedCardNumber => maskedCardNumber;

  String get maskedCardNumber {
    if (_cardNumber.length >= 16) {
      return '**** **** **** ${_cardNumber.substring(12)}';
    }
    return '**** ${_cardNumber.substring(_cardNumber.length - 4)}';
  }

  @override
  String toString() {
    return 'CardData(cardNumber: $maskedCardNumber, expiryDate: $expiryDate, cardType: $cardType)';
  }
}
```
2. Never serialize full card number to JSON
3. Implement access logging for full PAN access

---

## 🟢 LOW PRIORITY ISSUES

### 12. NO SESSION TIMEOUT OR SECURITY LIFECYCLE

**Severity**: 🟢 LOW  
**Status**: ❌ UNRESOLVED

**Description**:
Card data persists in memory indefinitely after reading. No automatic clearing or timeout mechanism exists.

**Affected Files**:
- `lib/providers/nfc_provider.dart` (lines 14-119)

**Risk**:
- Extended exposure window if device left unlocked
- Data remains in memory longer than necessary
- Increased risk of memory dumps

**Remediation**:
1. Implement auto-clear timer:
```dart
class NfcProvider extends ChangeNotifier {
  Timer? _clearTimer;
  static const _dataTimeout = Duration(minutes: 5);
  
  Future<void> readCard() async {
    // ... existing code ...
    
    if (card != null) {
      _cardData = card;
      _state = NfcState.success;
      
      // Auto-clear after timeout
      _clearTimer?.cancel();
      _clearTimer = Timer(_dataTimeout, () {
        clearCardData();
      });
    }
  }
  
  void clearCardData() {
    _cardData = null;
    _state = NfcState.idle;
    notifyListeners();
  }
  
  @override
  void dispose() {
    _clearTimer?.cancel();
    super.dispose();
  }
}
```
2. Clear data when app goes to background
3. Implement re-authentication for viewing after timeout
4. Zero out memory when clearing sensitive data

---

## COMPLIANCE VIOLATIONS

### PCI DSS (Payment Card Industry Data Security Standard)

| Requirement | Status | Issue |
|------------|--------|-------|
| 3.3 - Mask PAN when displayed | ⚠️ PARTIAL | Full card shown in UI (#4) |
| 3.4 - Render PAN unreadable | ❌ FAIL | No encryption (#1) |
| 4.1 - Use strong cryptography | ❌ FAIL | No encryption in transit (#1) |
| 10.2 - Audit logs must not contain full PAN | ❌ FAIL | Debug logging (#2) |
| 12.3 - Usage policies for critical technologies | ⚠️ MISSING | No security policies |

### GDPR (General Data Protection Regulation)

- **Article 32** - Security of processing: VIOLATED (no encryption)
- **Article 25** - Data protection by design: VIOLATED (insecure by default)
- **Article 5** - Data minimization: VIOLATED (excessive logging)

### CCPA (California Consumer Privacy Act)

- Reasonable security procedures: VIOLATED (no encryption, insecure logging)

---

## TESTING RECOMMENDATIONS

### Security Testing Checklist

- [ ] Penetration testing by certified security professional
- [ ] Static Application Security Testing (SAST)
- [ ] Dynamic Application Security Testing (DAST)
- [ ] Mobile Application Security Testing (MAST)
- [ ] Code review by security expert
- [ ] Threat modeling exercise
- [ ] Vulnerability scanning
- [ ] Compliance audit (PCI DSS)

### Tools to Use

1. **Static Analysis**:
   - MobSF (Mobile Security Framework)
   - QARK (Quick Android Review Kit)
   - Checkmarx

2. **Dynamic Analysis**:
   - Frida (runtime instrumentation)
   - Burp Suite (network traffic analysis)
   - OWASP ZAP

3. **Reverse Engineering**:
   - jadx (Java decompiler)
   - apktool (APK analysis)
   - Hopper Disassembler (iOS)

---

## IMPLEMENTATION PRIORITY

### Phase 1: IMMEDIATE (Before ANY Production Use)
**Timeline**: 1-2 days

1. ✅ Remove/disable all debug logging of card data (#2)
2. ✅ Implement encryption for card data (#1)
3. ✅ Mask card numbers in UI (#4)
4. ✅ Disable "Save Card" functionality until secure storage implemented (#3)

### Phase 2: HIGH PRIORITY (Before Release)
**Timeline**: 3-5 days

5. ✅ Implement proper release signing (#5)
6. ✅ Add secure storage mechanism (#3)
7. ✅ Implement certificate pinning (#6)
8. ✅ Add comprehensive input validation (#7)

### Phase 3: MEDIUM PRIORITY (Before Public Release)
**Timeline**: 5-7 days

9. ✅ Enable code obfuscation (#8)
10. ✅ Add security configurations (#9)
11. ✅ Implement runtime security checks (#10)
12. ✅ Refactor CardData model (#11)

### Phase 4: LOW PRIORITY (Post-Release Enhancement)
**Timeline**: Ongoing

13. ✅ Implement session timeout (#12)
14. ✅ Add biometric authentication
15. ✅ Implement security logging and monitoring
16. ✅ Regular security audits

---

## RESOURCES

### Recommended Reading

1. [OWASP Mobile Security Testing Guide](https://owasp.org/www-project-mobile-security-testing-guide/)
2. [PCI DSS Requirements](https://www.pcisecuritystandards.org/document_library)
3. [Flutter Security Best Practices](https://docs.flutter.dev/security)
4. [Android Security Best Practices](https://developer.android.com/topic/security/best-practices)
5. [iOS Security Guide](https://support.apple.com/guide/security/welcome/web)

### Recommended Packages

```yaml
dependencies:
  flutter_secure_storage: ^9.0.0
  encrypt: ^5.0.3
  cryptography: ^2.7.0
  flutter_jailbreak_detection: ^1.10.0
  safe_device: ^1.1.5
  local_auth: ^2.1.7
```

---

## CONCLUSION

The Cards Wallet NFC application has **significant security vulnerabilities** that must be addressed before any production use. The most critical issues involve the handling of sensitive payment card data without encryption and excessive debug logging.

**Recommendations**:
1. **DO NOT** deploy this application to production in its current state
2. **DO NOT** use for reading real payment cards until encryption is implemented
3. **IMMEDIATELY** address Critical and High priority issues
4. Conduct professional security audit before release
5. Implement continuous security monitoring
6. Regular security updates and patches

**Estimated Remediation Time**: 2-3 weeks for full security implementation

---

**Document Version**: 1.0  
**Last Updated**: December 31, 2025  
**Next Review**: After remediation implementation

