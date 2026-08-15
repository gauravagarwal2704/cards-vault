# Changelog

## [Enhanced] - 2025-01-01

### 🎯 Major Enhancements

#### RuPay Card Support
- ✅ Added RuPay card detection with priority-based prefix matching
- ✅ Supports RuPay prefixes: 60, 6521, 6522, 607, 608
- ✅ Added RuPay AIDs: `A0000005241010` (standard), `A000000524` (domestic)

#### Multiple AID Support
- ✅ Changed `_extractAID()` to `_extractAIDs()` - now extracts **all** AIDs from PPSE
- ✅ Tries each AID sequentially until one succeeds
- ✅ No longer fails if first AID doesn't work

#### Known Payment AID Fallback
- ✅ Added `_tryKnownAIDs()` method with 10+ known payment AIDs:
  - Visa: Standard, Electron, Interlink, Plus
  - Mastercard: Standard, Maestro, Debit, Credit
  - RuPay: Standard, Domestic
- ✅ Automatically falls back to known AIDs if PPSE fails or all PPSE AIDs fail

#### Strict ISO 7816-4 Compliance
- ✅ Added Le byte (`00`) to all APDU commands:
  - SELECT AID: `00A4040007{AID}00` (was missing Le)
  - GPO: `80A800000283000000` (was `80A8000002830000`)
  - GPO with PDOL: `80A80000{LENGTH}83{PDOL_LENGTH}{PDOL_DATA}00`
  - READ RECORD: `00B2{RECORD}{SFI}00` (already had Le, kept consistent)
- ✅ Fixes error `6700` (Wrong length) on strict domestic cards

#### PPSE Failure Handling
- ✅ Wrapped PPSE selection in try-catch
- ✅ Gracefully handles cards that don't support PPSE
- ✅ Falls back to known AIDs if PPSE fails

#### Enhanced Debugging
- ✅ Enabled debug logging in `debug_logger.dart`
- ✅ Comprehensive logging at every step
- ✅ Logs all AIDs tried and which one succeeded
- ✅ Helps diagnose card-specific issues

### 🐛 Bug Fixes

#### Domestic Card Support
- **Issue**: Axis Bank Priority Debit Card (Visa Platinum - Domestic) was failing with error `6700`
- **Root Cause**: Missing Le byte in APDU commands
- **Solution**: Added Le byte to all APDU commands
- **Result**: ✅ Now works with both international and domestic cards

#### Debit Card Scanning
- **Issue**: Debit cards were failing to scan (NFC detected but scanning failed)
- **Root Cause**: Only first AID was tried; many debit cards have multiple AIDs
- **Solution**: Extract and try all AIDs sequentially
- **Result**: ✅ Debit cards now scan successfully

### 📝 Documentation Updates

#### README.md
- Updated features list with RuPay and multiple AID support
- Updated EMV flow to show multiple AID trying
- Updated APDU commands with Le byte notation
- Added RuPay to card type detection table
- Added "Enhanced Compatibility" section explaining domestic vs international cards

#### TECHNICAL_REFERENCE.md
- Updated all APDU command examples with Le byte
- Added detailed explanation of Le byte requirement
- Updated status codes with `6700` error explanation
- Added RuPay AIDs to known payment AIDs table
- Added "Domestic vs International Cards" section
- Enhanced "Common Issues & Solutions" with Le byte troubleshooting

#### PROJECT_OVERVIEW.md
- Updated supported card types with RuPay
- Added "Recent Enhancements" section
- Updated code metrics (750+ lines in NFC service)
- Updated EMV protocol support description

#### IMPLEMENTATION_SUMMARY.md
- Updated technical flow with multiple AID support
- Updated APDU commands with Le byte examples
- Added tested cards section
- Updated code statistics
- Added "Recent Enhancements" to conclusion

### 🔧 Technical Changes

#### Files Modified

1. **lib/services/nfc_service.dart** (370 → 750+ lines)
   - `_extractAID()` → `_extractAIDs()` returning `List<String>`
   - Added `_tryKnownAIDs()` method
   - Enhanced `readCard()` with multiple AID trying and PPSE fallback
   - Updated `_determineCardType()` with RuPay detection
   - Added Le byte to GPO command building

2. **lib/services/apdu_commands.dart**
   - Updated `selectAID()` to include Le byte
   - Updated `gpoCommand` constant to include Le byte
   - Updated `readRecord()` to include Le byte

3. **lib/utils/debug_logger.dart**
   - Enabled logging with `dart:developer` and print statements
   - Helps troubleshoot card-specific issues

4. **Documentation Files**
   - README.md - Enhanced with all changes
   - TECHNICAL_REFERENCE.md - Detailed technical updates
   - PROJECT_OVERVIEW.md - Updated metrics and features
   - IMPLEMENTATION_SUMMARY.md - Complete change summary

### 🎯 Compatibility Matrix

| Card Type | Example | Before | After |
|-----------|---------|--------|-------|
| International Credit | HDFC Visa Platinum Credit | ✅ Works | ✅ Works |
| International Debit | HDFC Visa Platinum Debit | ✅ Works | ✅ Works |
| Domestic Debit | Axis Bank Visa Platinum Debit | ❌ Failed (6700) | ✅ Works |
| RuPay Credit | Any RuPay Credit | ❌ Not Detected | ✅ Works |
| RuPay Debit | Any RuPay Debit | ❌ Not Detected | ✅ Works |

### 📊 Statistics

- **Lines of Code Added**: ~400+ lines
- **New Methods**: 2 (`_extractAIDs()`, `_tryKnownAIDs()`)
- **Known AIDs**: 10+ (was 0)
- **Supported Networks**: 7 (was 6)
- **Card Compatibility**: Significantly improved
- **Linter Errors**: 0 (maintained)

### 🚀 Impact

- ✅ **Debit cards now work** - Fixed the primary issue
- ✅ **RuPay support added** - India's domestic network supported
- ✅ **Domestic cards work** - No longer limited to international cards
- ✅ **Better reliability** - Multiple fallback mechanisms
- ✅ **Enhanced debugging** - Easier to diagnose issues
- ✅ **Maintained quality** - Zero linter errors, clean code

---

## [Initial Release] - 2024-12-XX

### Initial Implementation
- ✅ Basic NFC card reading
- ✅ EMV protocol implementation
- ✅ PPSE selection
- ✅ Single AID extraction
- ✅ GPO and record reading
- ✅ Card data extraction
- ✅ Beautiful UI
- ✅ Error handling
- ✅ Documentation

---

**Latest Version**: Enhanced with RuPay support, multiple AID fallback, and strict ISO 7816-4 compliance

