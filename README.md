# Cards Wallet - NFC Credit Card Reader

A Flutter application that reads credit card data via NFC on Android devices using EMV chip technology.

## Features

- ✅ **NFC Card Reading** - Read credit card data directly from EMV chips on Android
- ✅ **EMV Protocol Support** - Full implementation of PPSE selection, AID selection, GPO, and record reading
- ✅ **Multiple Card Types** - Supports Visa, Mastercard, American Express, Discover, JCB, UnionPay, and RuPay
- ✅ **Multiple AID Support** - Tries all available AIDs with fallback to known payment AIDs
- ✅ **Domestic & International Cards** - Works with both international and domestic-only debit/credit cards
- ✅ **Beautiful UI** - Modern, intuitive interface with real-time scanning feedback
- ✅ **Security Focused** - Includes encryption reminders and security best practices
- ✅ **iOS Fallback** - Graceful handling with camera OCR suggestion for iOS devices
- ✅ **Enhanced Compatibility** - Strict ISO 7816-4 compliance for maximum card compatibility

## Platform Support

| Platform | NFC Support | Status |
|----------|-------------|--------|
| Android  | ✅ Full Support | Reads EMV chip data via NFC |
| iOS      | ❌ Not Supported | CoreNFC blocks payment AIDs - Camera OCR recommended |

## Technical Implementation

### EMV Reading Flow

```
1. Poll for ISO7816/IsoDep NFC Tags
2. Select PPSE (2PAY.SYS.DDF01)
3. Parse Response to Extract All AIDs
4. Try Each AID Sequentially Until One Succeeds
5. Fallback to Known Payment AIDs (Visa, Mastercard, RuPay, etc.)
6. Send Get Processing Options (GPO)
7. Read Records from AFL (Application File Locator)
8. Extract PAN (Card Number) and Expiry Date
```

### APDU Commands Used

- **SELECT PPSE**: `00A404000E325041592E5359532E444446303100`
- **SELECT AID**: `00A4040007{AID}00` (dynamic based on card, includes Le byte)
- **GPO**: `80A800000283000000` (includes Le byte for strict cards)
- **READ RECORD**: `00B2{RECORD}{SFI}00` (dynamic based on AFL, includes Le byte)

### Data Extracted

- ✅ **Card Number (PAN)** - Tag `5A` or `57` (Track 2 Equivalent)
- ✅ **Expiry Date** - Tag `5F24` (YYMMDD format)
- ✅ **Cardholder Name** - Tag `5F20` (optional, if available)
- ✅ **Card Type** - Determined from PAN prefix
- ❌ **CVV** - Cannot be read via NFC (not stored on chip)

## Setup Instructions

### Prerequisites

- Flutter SDK (3.4.4 or higher)
- Android device with NFC capability (API 19+)
- Physical credit/debit card with EMV chip

### Installation

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd cards-vault
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Run the app**
   ```bash
   flutter run
   ```

### Android Configuration

The following permissions are already configured in `AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.NFC" />
<uses-feature android:name="android.hardware.nfc" android:required="false" />
```

**Minimum SDK**: Android 4.4 (API 19)

## Project Structure

```
lib/
├── main.dart                          # App entry point with Provider setup
├── models/
│   └── card_data.dart                 # Card data model (PAN, expiry, etc.)
├── services/
│   ├── nfc_service.dart               # Core NFC service with EMV logic
│   └── apdu_commands.dart             # APDU command constants and helpers
├── providers/
│   └── nfc_provider.dart              # Provider for NFC state management
├── screens/
│   └── add_card_screen.dart           # UI screen with "Tap to Add Card" button
└── utils/
    └── hex_utils.dart                 # Hex conversion utilities
```

## Usage

### Reading a Card

1. Launch the app on an Android device with NFC enabled
2. Tap the **"Tap to Add Card"** button
3. Hold your credit/debit card near the back of your device
4. Keep the card steady until scanning completes
5. View the extracted card details

### Error Handling

The app handles various error scenarios:

- **NFC Not Available** - Shows warning if device doesn't support NFC
- **NFC Disabled** - Prompts user to enable NFC in settings
- **Card Removed Early** - Asks user to hold card steady
- **Timeout** - 30-second session timeout with retry option
- **Unsupported Card** - Handles non-EMV or incompatible cards
- **iOS Platform** - Shows message to use camera instead

## Security Considerations

⚠️ **IMPORTANT SECURITY NOTES**

### Encryption Required

The code includes `TODO: ENCRYPT THIS DATA IMMEDIATELY` comments at critical points where sensitive card data is extracted. In production:

1. **Encrypt immediately** after reading PAN and expiry date
2. Use **Flutter Secure Storage** or similar encryption mechanism
3. Never store card data in plain text
4. Implement **PCI DSS compliance** measures

### What Cannot Be Read

- **CVV/CVC** - Not stored on EMV chip (only printed on physical card)
- **PIN** - Never stored or transmitted
- **Full Track Data** - Limited to what's available on chip

### Best Practices

```dart
// Example: Encrypt card data before storage
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage();
await storage.write(key: 'card_number', value: encryptedPAN);
```

## Dependencies

```yaml
dependencies:
  flutter_nfc_kit: ^3.3.1    # NFC operations with low-level APDU access
  provider: ^6.1.1            # State management
```

## Testing

### Test Cards

Test with various card types:
- Visa (starts with 4)
- Mastercard (starts with 5)
- American Express (starts with 34 or 37)
- Discover (starts with 6011 or 65)

### Test Scenarios

- ✅ Successful card read
- ✅ Card removed during scan
- ✅ NFC disabled
- ✅ Timeout scenario
- ✅ Multiple card types
- ✅ iOS platform handling

## Troubleshooting

### NFC Not Working

1. **Enable NFC**: Settings → Connected devices → Connection preferences → NFC
2. **Check Device**: Ensure device has NFC hardware
3. **Card Position**: Try different positions on the back of the device
4. **Remove Case**: Thick cases may interfere with NFC signal

### Card Not Reading

1. **EMV Chip**: Ensure card has a chip (not just magnetic stripe)
2. **Card Type**: Some cards may use different EMV implementations
3. **Hold Steady**: Keep card still during entire scan process
4. **Try Again**: Some cards require multiple attempts

### App Crashes

1. **Check Logs**: `flutter logs` to see detailed error messages
2. **Update Flutter**: Ensure you're using latest stable Flutter version
3. **Clean Build**: `flutter clean && flutter pub get`

## Known Limitations

- **iOS Support**: CoreNFC blocks payment AIDs for security reasons
- **NFC Range**: Very short range (< 4cm) - card must be very close
- **Read Speed**: Can take 3-10 seconds depending on card and device

## Enhanced Compatibility

### Domestic vs International Cards

The app now supports both international and domestic-only cards:

- **International Cards** (e.g., HDFC International Debit): Full PPSE support, lenient command format
- **Domestic Cards** (e.g., Axis Bank Priority Debit): May have limited PPSE, requires strict ISO 7816-4 compliance

### Multiple AID Support

- Extracts **all** AIDs from PPSE response
- Tries each AID sequentially until one succeeds
- Falls back to 10+ known payment AIDs including:
  - Visa (standard, Electron, Interlink, Plus)
  - Mastercard (standard, Maestro, Debit, Credit)
  - RuPay (standard, Domestic)

### Strict APDU Compliance

All APDU commands include the Le (expected length) byte for maximum compatibility with strict cards that require full ISO 7816-4 compliance.

## Future Enhancements

- [ ] Camera OCR for iOS devices
- [ ] Card storage with encryption
- [ ] Multiple card management
- [ ] Card verification
- [ ] Transaction history
- [ ] Biometric authentication
- [ ] Dark mode support

## Technical Details

### TLV Parsing

The app uses BER-TLV (Basic Encoding Rules - Tag Length Value) parsing to extract data from EMV responses:

- **Tag**: Identifies the data element (e.g., `5A` for PAN)
- **Length**: Size of the value in bytes
- **Value**: The actual data

### Card Type Detection

Card types are determined by PAN prefix:

| Prefix | Card Type |
|--------|-----------|
| 4      | Visa |
| 5      | Mastercard |
| 34, 37 | American Express |
| 6011   | Discover |
| 6522, 6521 | RuPay |
| 608, 607, 606 | RuPay |
| 65     | Discover |
| 60     | RuPay |
| 35     | JCB |
| 62     | UnionPay |

**Note**: RuPay detection uses priority-based matching (4-digit > 3-digit > 2-digit) to avoid conflicts.

## Contributing

Contributions are welcome! Please ensure:

1. Code follows Flutter best practices
2. Security considerations are maintained
3. All features are tested on real devices
4. Documentation is updated

## License

This project is for educational purposes. Please ensure compliance with:

- PCI DSS standards for production use
- Local regulations regarding payment card data
- Card network rules (Visa, Mastercard, etc.)

## Disclaimer

⚠️ **This application is for educational and development purposes only.**

- Do not use in production without proper security audits
- Implement full PCI DSS compliance for production use
- Ensure proper encryption and secure storage
- Follow all applicable laws and regulations
- Card data must be handled according to payment card industry standards

## Support

For issues, questions, or contributions:
- Open an issue on GitHub
- Review existing documentation
- Check troubleshooting section

---

**Built with Flutter & NFC Kit** 📱💳
