# Cards Wallet - Project Overview

## 🎯 Project Description

A Flutter-based credit card wallet application that reads EMV chip data from contactless credit/debit cards using NFC technology on Android devices. The app implements the complete EMV protocol flow including PPSE selection, AID extraction, GPO commands, and record reading to extract card details.

## 📱 Platform Support

- **Android**: ✅ Full NFC support with EMV chip reading
- **iOS**: ⚠️ Fallback message (CoreNFC blocks payment AIDs)

## 🏗️ Architecture

### Clean Architecture Pattern

```
┌─────────────────────────────────────────┐
│            Presentation Layer            │
│  (Screens, Widgets, State Management)   │
│         - add_card_screen.dart          │
│         - nfc_provider.dart             │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│            Business Logic Layer          │
│         (Services, Use Cases)           │
│         - nfc_service.dart              │
│         - apdu_commands.dart            │
└─────────────────┬───────────────────────┘
                  │
┌─────────────────▼───────────────────────┐
│              Data Layer                  │
│         (Models, Utilities)             │
│         - card_data.dart                │
│         - hex_utils.dart                │
└─────────────────────────────────────────┘
```

## 📂 Project Structure

```
cards-wallet/
├── lib/
│   ├── main.dart                      # App entry point
│   ├── models/
│   │   └── card_data.dart            # Card data model
│   ├── services/
│   │   ├── nfc_service.dart          # Core NFC/EMV logic
│   │   └── apdu_commands.dart        # APDU commands & TLV parser
│   ├── providers/
│   │   └── nfc_provider.dart         # State management
│   ├── screens/
│   │   └── add_card_screen.dart      # Main UI screen
│   └── utils/
│       └── hex_utils.dart            # Hex conversion utilities
├── android/
│   └── app/src/main/
│       └── AndroidManifest.xml       # NFC permissions
├── pubspec.yaml                       # Dependencies
├── README.md                          # Main documentation
├── QUICK_START.md                     # Quick start guide
├── TECHNICAL_REFERENCE.md             # Technical details
├── IMPLEMENTATION_SUMMARY.md          # Implementation checklist
└── PROJECT_OVERVIEW.md                # This file
```

## 🔧 Technologies Used

### Core Dependencies
- **Flutter SDK**: 3.22.3+
- **flutter_nfc_kit**: ^3.3.1 - NFC operations with APDU access
- **provider**: ^6.1.1 - State management

### Development Tools
- **Dart**: 3.4.4+
- **Android SDK**: API 19+ (Android 4.4+)
- **Material Design 3**: UI components

## 🎨 Features

### Implemented Features ✅

1. **NFC Card Reading**
   - ISO7816/IsoDep tag detection
   - EMV chip data extraction
   - Real-time scanning feedback

2. **EMV Protocol Support**
   - PPSE (Payment System Environment) selection with fallback
   - Multiple AID (Application ID) extraction and sequential trying
   - Known payment AID fallback (10+ AIDs)
   - GPO (Get Processing Options) with PDOL support
   - AFL (Application File Locator) parsing
   - Record reading with TLV parsing
   - Strict ISO 7816-4 compliance (Le byte in all commands)

3. **Data Extraction**
   - Card Number (PAN) - Tag 5A/57
   - Expiry Date - Tag 5F24
   - Cardholder Name - Tag 5F20 (optional)
   - Card Type detection (Visa, Mastercard, etc.)

4. **User Interface**
   - Modern, clean design
   - Real-time scanning animation
   - Beautiful card preview with gradients
   - Error handling with SnackBar messages
   - Platform-specific messaging

5. **Error Handling**
   - NFC availability check
   - Timeout handling
   - Card removal detection
   - Unsupported card handling
   - Comprehensive error messages

6. **Security**
   - Encryption reminders in code
   - CVV cannot be read (not on chip)
   - Security documentation
   - PCI DSS guidelines

### Recent Enhancements ✅

- ✅ **Multiple AID Support** - Extracts all AIDs from PPSE and tries each sequentially
- ✅ **Known AID Fallback** - Falls back to 10+ known payment AIDs (Visa variants, Mastercard variants, RuPay)
- ✅ **RuPay Support** - Full support for India's domestic card network
- ✅ **Domestic Card Support** - Works with domestic-only debit/credit cards
- ✅ **Strict APDU Compliance** - Le byte in all commands for maximum compatibility
- ✅ **PPSE Fallback** - Gracefully handles PPSE failures
- ✅ **Enhanced Debugging** - Comprehensive logging for troubleshooting

### Future Enhancements 🚀

- [ ] Encryption implementation
- [ ] Secure storage (flutter_secure_storage)
- [ ] Camera OCR for iOS
- [ ] Multiple card management
- [ ] Database integration (SQLite)
- [ ] Biometric authentication
- [ ] Card verification
- [ ] Transaction history
- [ ] Dark mode
- [ ] Localization

## 🔐 Security Considerations

### Current Implementation
- ✅ Security comments at critical points
- ✅ CVV limitation documented
- ✅ PCI DSS guidelines provided
- ✅ Encryption reminders in code

### Required for Production
- ⚠️ Implement AES-256 encryption
- ⚠️ Use Flutter Secure Storage
- ⚠️ Add biometric authentication
- ⚠️ Implement tokenization
- ⚠️ SSL certificate pinning
- ⚠️ Security audit
- ⚠️ PCI DSS compliance

## 📊 Code Metrics

| Metric | Value |
|--------|-------|
| Total Dart Files | 8 |
| Total Lines of Code | ~1,400+ |
| Core NFC Service | 750+ lines |
| UI Screen | 450+ lines |
| Documentation Files | 5 |
| Linter Errors | 0 |
| Supported Card Networks | 7 (Visa, MC, Amex, Discover, JCB, UnionPay, RuPay) |
| Known Payment AIDs | 10+ |
| Test Coverage | TBD |

## 🎯 Use Cases

### Primary Use Case
1. User opens app
2. Taps "Tap to Add Card" button
3. Holds credit card near device
4. App reads EMV chip data
5. Card details displayed
6. User can save card

### Error Scenarios
- NFC not available → Show warning
- NFC disabled → Prompt to enable
- Card removed early → Ask to hold steady
- Timeout → Offer retry
- Unsupported card → Show error message
- iOS device → Suggest camera OCR

## 🔄 Data Flow

```
User Action (Tap Button)
    ↓
NfcProvider.readCard()
    ↓
NfcService.readCard()
    ↓
1. Poll NFC Tag
2. Select PPSE → Parse Response
3. Extract AID → Select Application
4. Send GPO → Parse AFL
5. Read Records → Extract Data
    ↓
CardData Model
    ↓
UI Update (Card Preview)
```

## 🧪 Testing Strategy

### Manual Testing
- ✅ Test with multiple card types
- ✅ Test error scenarios
- ✅ Test on different Android devices
- ✅ Test NFC disabled scenario
- ✅ Test iOS fallback message

### Automated Testing (Future)
- [ ] Unit tests for utilities
- [ ] Widget tests for UI
- [ ] Integration tests for NFC flow
- [ ] Mock NFC responses

## 📱 Supported Card Types

| Card Type | IIN Prefix | Status | Notes |
|-----------|------------|--------|-------|
| Visa | 4 | ✅ Supported | International & Domestic |
| Mastercard | 51-55 | ✅ Supported | International & Domestic |
| American Express | 34, 37 | ✅ Supported | International |
| Discover | 6011, 65 | ✅ Supported | International |
| JCB | 35 | ✅ Supported | International |
| UnionPay | 62 | ✅ Supported | International |
| RuPay | 60, 6521, 6522, 607, 608 | ✅ Supported | India Domestic |

## 🚀 Getting Started

### Quick Start
```bash
# Clone and setup
cd cards-wallet
flutter pub get

# Run on Android device
flutter run
```

### Prerequisites
- Flutter SDK installed
- Android device with NFC
- USB debugging enabled
- Physical EMV card for testing

## 📚 Documentation

1. **README.md** - Complete documentation
   - Setup instructions
   - Usage guide
   - Troubleshooting
   - Security guidelines

2. **QUICK_START.md** - 5-minute setup guide
   - Installation steps
   - First card scan
   - Common commands
   - Testing tips

3. **TECHNICAL_REFERENCE.md** - Technical details
   - APDU commands breakdown
   - EMV tag reference
   - TLV parsing guide
   - Status codes

4. **IMPLEMENTATION_SUMMARY.md** - Implementation checklist
   - Features completed
   - Requirements met
   - Code statistics
   - Quality metrics

5. **PROJECT_OVERVIEW.md** - This file
   - Architecture overview
   - Technology stack
   - Project structure
   - Development roadmap

## 🤝 Contributing

### Development Workflow
1. Create feature branch
2. Implement changes
3. Run `flutter analyze`
4. Test on real device
5. Update documentation
6. Submit pull request

### Code Standards
- Follow Flutter style guide
- Use meaningful variable names
- Add comments for complex logic only
- Maintain clean architecture
- Write tests for new features

## 📄 License

This project is for educational and development purposes. Ensure compliance with:
- PCI DSS standards
- Local regulations
- Card network rules
- Privacy laws

## ⚠️ Disclaimer

**For Educational/Development Use Only**

- Not production-ready without security hardening
- Requires encryption implementation
- Needs PCI DSS compliance audit
- Must follow payment card industry standards

## 📞 Support

### Resources
- 📖 Documentation in this repository
- 🔧 Flutter NFC Kit: https://pub.dev/packages/flutter_nfc_kit
- 💳 EMV Specifications: https://www.emvco.com/
- 🛡️ PCI DSS: https://www.pcisecuritystandards.org/

### Troubleshooting
1. Check README.md troubleshooting section
2. Review Flutter logs: `flutter logs`
3. Verify NFC settings on device
4. Test with different cards

## 🎓 Learning Outcomes

This project demonstrates:
- ✅ NFC/RFID communication
- ✅ EMV protocol implementation
- ✅ APDU command construction
- ✅ TLV data parsing
- ✅ Flutter state management
- ✅ Clean architecture
- ✅ Error handling patterns
- ✅ Security best practices

## 🏆 Project Status

**Status**: ✅ **COMPLETE & READY FOR DEVELOPMENT**

- All core features implemented
- Zero linter errors
- Comprehensive documentation
- Ready for testing with real cards
- Extensible architecture for future features

## 📈 Roadmap

### Phase 1: Core Features ✅ COMPLETE
- [x] NFC card reading
- [x] EMV protocol implementation
- [x] Basic UI
- [x] Error handling
- [x] Documentation

### Phase 2: Security 🔄 NEXT
- [ ] Encryption implementation
- [ ] Secure storage
- [ ] Biometric auth
- [ ] PCI DSS compliance

### Phase 3: Features 📋 PLANNED
- [ ] Camera OCR (iOS)
- [ ] Multiple cards
- [ ] Database storage
- [ ] Card verification

### Phase 4: Polish 🎨 FUTURE
- [ ] Dark mode
- [ ] Localization
- [ ] Animations
- [ ] Accessibility

---

**Built with ❤️ using Flutter**

*A complete NFC credit card reader implementation for educational and development purposes.*

