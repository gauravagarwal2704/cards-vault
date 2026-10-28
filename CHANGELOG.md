# Changelog

## [1.8.19+38] - 2026-10-28

### Fixed
- Cards appear sooner when opening your wallet, with fewer secure-storage calls and search and filter details loaded in the background.

## [1.8.18+37] - 2026-10-22

### Changed
- Prepared a fresh Google Play closed-testing build with the latest CardVault improvements. App features are unchanged from the previous version.

## [1.8.17+36] - 2026-10-22

### Changed
- Homepage carousel cards now show the contactless symbol in the same position as the card preview, respecting the Show on card setting.

## [1.8.16+35] - 2026-10-22

### Changed
- Custom-image alignment now uses the main card preview for dragging, pinching, zooming, and reset, without a duplicate preview in the image selection section.

## [1.8.15+34] - 2026-10-22

### Changed
- Moved the vertical Credit Card and Debit Card labels to the left edge of homepage carousel cards to match the card details preview.

## [1.8.14+33] - 2026-10-22

### Changed
- Additional Information always shows copy buttons, with empty fields disabled until a value is saved.

## [1.8.13+32] - 2026-10-22

### Changed
- Copy saved notes from Additional Information, with consistent labeled copy buttons for account numbers, IFSC codes, UPI IDs, and notes.

## [1.8.12+31] - 2026-10-22

### Changed
- Card background reveals now finish in 400 milliseconds, and timing adjustments apply to previews that are already open.

## [1.8.11+30] - 2026-10-22

### Changed
- Sped up the entire card background reveal while preserving its smooth motion.

## [1.8.10+29] - 2026-10-22

### Changed
- Card background reveals start a little faster while keeping their smooth finish.

## [1.8.9+28] - 2026-10-22

### Changed
- Smoothed card background reveals with gentler timing, images loaded before the animation, and uninterrupted transitions when selecting designs quickly.

## [1.8.8+27] - 2026-10-22

### Changed
- Selected card designs and background images reveal with an expanding circle from a random point on the add and edit previews.
- Reveal animations respect the device setting to reduce motion.

## [1.8.7+26] - 2026-10-22

### Changed
- Reduced the gap below the sticky card preview on add and edit pages for a more compact scrolling layout.

## [1.8.6+25] - 2026-10-22

### Changed
- The card preview stays visible while scrolling on add and edit pages, with a subtle lift animation and live design updates.

## [1.8.5+24] - 2026-10-10

### Changed
- Restyled “Buy me a Chai” to match the Coffee button more closely with a reduced corner radius and a chai cup icon.

## [1.8.4+23] - 2026-10-10

### Changed
- Updated the Chai support shortcut label to “Buy me a Chai” while keeping it beside the Buy me a coffee button.

## [1.8.3+22] - 2026-10-10

### Changed
- Replaced the custom Coffee shortcut with the supplied official “Buy me a coffee” artwork and kept Coffee and Chai side by side.

## [1.8.2+21] - 2026-10-10

### Changed
- Updated the Buy Me a Coffee shortcut with the requested “Buy me a pizza” label, pizza emoji, coral background, and white text.

## [1.8.1+20] - 2026-10-10

### Added
- Coffee and Chai external contribution shortcuts on the supporter page alongside the Google Play Supporter Star options.

## [1.8.0+19] - 2026-10-10

### Added
- An optional supporter page, opened from the CardVault icon or Support shortcut in Settings, with localized Google Play Supporter Star products, three quick amounts, and a custom configured-amount picker.
- Repeatable consumable purchase handling for successful, pending, cancelled, and failed Google Play transactions. Each purchase adds one cosmetic Supporter Star while every functional feature remains available to everyone.
- Google Play tip product setup and testing guidance in `docs/google-play-tips-setup.md`.

### Changed
- Replaced the external Coffee and Chai payment shortcuts with the in-app Google Play Support flow.
- Updated the in-app and published privacy policy source to explain optional payment handling.

## [1.7.4+18] - 2026-10-10

### Changed
- Increased horizontal and vertical spacing between color theme tiles from 4 to 12 logical pixels, keeping the three-column layout.

## [1.7.3+17] - 2026-10-10

### Fixed
- Debug and profile builds launch MainActivity directly, preventing Flutter from launching a disabled default icon alias after another icon is selected. Variant manifests remove launcher filters from icon aliases to avoid duplicate launcher entries. Release builds retain selectable launcher icons.

## [1.7.2+16] - 2026-10-10

### Fixed
- Palette style comparison tiles generate distinct Tonal Spot and Expressive previews from the same base color rather than duplicating the device scheme. The section explains that Device colors retain the system style.
- Reduced Device colors padding/icon size, preset tile padding/label space, and preset grid gaps for a more compact layout.
- Widened the three-circle preview to include the entire final circle, with scaling for narrow tiles.

## [1.7.1+15] - 2026-10-10

### Fixed
- Tonal Spot and Expressive appear side by side with labeled previews of button and tonal surface colors. Device color previews show the actual system scheme rather than the saved preset/custom seed.
- Color theme presets use three columns; selected presets, Device colors, and Custom color use filled highlights without colored selection borders.
- The Settings Appearance indicator reflects the active theme primary color after switching from a custom color to Device colors.

## [1.7.0+14] - 2026-10-10

### Added
- Eight muted Material 3 color themes: Lavender, Sage, Dusty rose, Sand, Powder blue, Peach, Mist, and Olive.

### Fixed
- New installations default to Tonal Spot. Returning users retain their saved palette styles and prior appearance choices.
- Device colors read Android 12+ system tonal palettes and Android 14+ color roles rather than continuing to generate colors from the previous preset. The palette refreshes on selection and app resume, applies to light/dark/OLED themes, and uses a disclosed Indigo fallback when unavailable.

## [1.6.0+13] - 2026-10-10

### Added
- Edit action in the left-swipe tray opens the existing card editor after the protected-edit authentication check and refreshes the wallet after saving.

### Changed
- Swipe actions are transparent circular outline buttons: Share uses the theme primary color, Delete uses the theme error red, and Edit uses the app's blue info color. All three fit together on smaller cards.

## [1.5.2+12] - 2026-10-10

### Fixed
- Card swipe action buttons and their shadows now use the app theme primary color instead of fixed blue and red. Icons and labels use the matching theme foreground color.

## [1.5.1+11] - 2026-10-10

### Fixed
- Custom-image overlay controls now use a filled selected state and a transparent, outlined deselected state.
- Hidden card overlays keep their layout slots so toggling logos, names, numbers, or dates does not move other elements in card previews, details, wallet tiles, or carousels. Hidden content remains excluded from painting and accessibility.
- Card numbers scale down on narrow previews to stay on one line.

## [1.5.0+10] - 2026-10-10

### Added
- Show/hide controls for network logo, bank logo, contactless symbol, card type, nickname, card number, cardholder name, and expiry date when using a custom card image. Previews update immediately.
- Per-card overlay visibility persists across editing, wallet views, card details, and backup/restore. Existing cards keep all overlays visible, and catalog/gradient backgrounds retain their standard layout.

## [1.4.0+9] - 2026-10-10

### Added
- Custom card image alignment with dragging, pinch zoom, a zoom slider, and reset. The live preview includes the entered card number.
- Saved image placement shared by add/edit previews, wallet views, card details, and backup/restore. Existing images default to their original centered crop.

### Fixed
- Removed the bank-colored shadow and underlying bank gradient from custom image backgrounds; images fill the card edge to edge.

## [1.3.0+8] - 2026-10-10

### Added
- Change history in Settings → About, showing dated release notes and build numbers.
- A project rule requiring version bumps based on change magnitude and matching in-app and repository records for every completed app change.

### Fixed
- Returning to the home page within the app no longer prompts for another unlock. App lock uses a two-minute grace period after leaving the app.
- Android's native card scanner keeps the current app session unlocked, allowing scan results to open the card editor for review and saving.

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
