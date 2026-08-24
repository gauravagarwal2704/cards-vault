# Quick Start Guide

## 🚀 Get Started in 5 Minutes

### Prerequisites
- ✅ Flutter SDK installed
- ✅ Android device with NFC
- ✅ Physical credit/debit card with EMV chip

### Installation

```bash
# 1. Navigate to project
cd cards-wallet

# 2. Install dependencies
flutter pub get

# 3. Connect Android device via USB

# 4. Enable USB debugging on device

# 5. Run the app
flutter run
```

### First Card Scan

1. **Enable NFC** on your Android device:
   - Settings → Connected devices → Connection preferences → NFC → ON

2. **Launch the app** on your device

3. **Tap "Tap to Add Card"** button

4. **Hold your card** near the back of your device
   - Keep it steady for 3-10 seconds
   - Don't remove until scan completes

5. **View card details** displayed on screen

### Project Structure

```
lib/
├── main.dart                    # App entry point
├── models/card_data.dart        # Card data model
├── services/
│   ├── nfc_service.dart         # NFC reading logic ⭐
│   └── apdu_commands.dart       # EMV commands
├── providers/nfc_provider.dart  # State management
├── screens/add_card_screen.dart # Main UI
└── utils/hex_utils.dart         # Helper functions
```

### Key Files to Understand

#### 1. `nfc_service.dart` - Core NFC Logic
```dart
// Main entry point for card reading
Future<CardData?> readCard() async {
  // 1. Poll for NFC tag
  // 2. Select PPSE
  // 3. Extract AID
  // 4. Select Application
  // 5. Get Processing Options
  // 6. Read Records
  // 7. Extract PAN & Expiry
}
```

#### 2. `apdu_commands.dart` - EMV Commands
```dart
// PPSE Selection Command
static const String selectPpse = "00A404000E325041592E5359532E444446303100";

// AID Selection (dynamic)
static String selectAID(String aid) { ... }

// Get Processing Options
static const String gpoCommand = "80A8000002830000";

// Read Record (dynamic)
static String readRecord(int recordNumber, int sfi) { ... }
```

#### 3. `nfc_provider.dart` - State Management
```dart
// Read card and update UI state
Future<void> readCard() async {
  _state = NfcState.scanning;
  CardData? card = await _nfcService.readCard();
  _state = NfcState.success;
}
```

### Common Commands

```bash
# Run on specific device
flutter run -d <device-id>

# Build APK
flutter build apk

# Check for issues
flutter analyze

# View logs
flutter logs

# Clean build
flutter clean && flutter pub get
```

### Testing

#### Test with Real Cards
- ✅ Visa
- ✅ Mastercard  
- ✅ American Express
- ✅ Discover

#### Test Scenarios
1. **Successful scan** - Normal card reading
2. **Card removed early** - Remove card during scan
3. **Timeout** - Don't place card near device
4. **Multiple scans** - Scan different cards
5. **NFC disabled** - Turn off NFC in settings

### Troubleshooting

#### "NFC not available"
- Check if device has NFC hardware
- Enable NFC in device settings

#### "Card not reading"
- Ensure card has EMV chip (not just magnetic stripe)
- Try different positions on back of device
- Remove phone case if thick
- Hold card steady for full duration

#### "Unsupported card"
- Some cards use non-standard EMV implementations
- Try another card to verify NFC is working

#### App crashes
```bash
# View detailed logs
flutter logs

# Clean and rebuild
flutter clean
flutter pub get
flutter run
```

### Customization

#### Change Scan Timeout
```dart
// In nfc_service.dart
NFCTag tag = await FlutterNfcKit.poll(
  timeout: const Duration(seconds: 30), // Change this
);
```

#### Customize UI Colors
```dart
// In add_card_screen.dart
List<Color> _getCardGradient(String cardType) {
  // Add your custom gradients here
}
```

#### Add Card Validation
```dart
// In card_data.dart
bool isValid() {
  return cardNumber.length >= 13 && 
         expiryDate.isNotEmpty;
}
```

### Next Steps

1. **Add Encryption**: Implement secure storage for card data
   ```dart
   import 'package:flutter_secure_storage/flutter_secure_storage';
   ```

2. **Card OCR**: Android scanning uses the native Tesseract4Android bridge in
   `android/app/src/main/kotlin/com/cardswallet/cards_wallet/ocr/`. iOS OCR is
   intentionally deferred.

3. **Add Database**: Store multiple cards
   ```dart
   import 'package:sqflite/sqflite.dart';
   ```

4. **Biometric Auth**: Secure app access
   ```dart
   import 'package:local_auth/local_auth.dart';
   ```

### Security Checklist

Before deploying to production:

- [ ] Implement encryption for card data
- [ ] Add secure storage (flutter_secure_storage)
- [ ] Implement PCI DSS compliance
- [ ] Add biometric authentication
- [ ] Mask card numbers in logs
- [ ] Implement tokenization
- [ ] Add SSL certificate pinning
- [ ] Conduct security audit

### Resources

- 📖 [README.md](README.md) - Full documentation
- 🔧 [TECHNICAL_REFERENCE.md](TECHNICAL_REFERENCE.md) - APDU commands & EMV details
- 📱 Flutter NFC Kit: https://pub.dev/packages/flutter_nfc_kit
- 💳 EMV Specifications: https://www.emvco.com/

### Support

Having issues? Check:
1. README.md troubleshooting section
2. Flutter logs: `flutter logs`
3. Device NFC settings
4. Card compatibility

---

**Happy Coding! 🎉**

Remember: This is for development/educational purposes. Implement proper security measures for production use.
