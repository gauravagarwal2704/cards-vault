# NFC Card Scanning Troubleshooting Guide

## Issues Addressed

### 1. Visa Platinum Card (428094...) - Not Scanning
**Problem**: Card not being detected at all during NFC scan

**Root Causes & Fixes**:
- Added Visa Platinum AID (`A0000000030000`) to known AIDs list
- Added Visa V Pay AID (`A0000000032020`) for additional Visa variants
- Increased NFC polling timeout from 30 to 60 seconds
- Added retry mechanism for transceive operations (up to 3 retries with exponential backoff)
- Improved tag type detection to handle more card types

### 2. RuPay Debit Card (608332...) - "Failed to read card" Error
**Problem**: Card detected but reading fails

**Root Causes & Fixes**:
- Enhanced RuPay card detection for BIN ranges starting with 6083, 6082
- Added RuPay Credit AID (`A0000005240010`)
- Improved error handling with detailed logging
- Added retry mechanism for transceive operations
- Better status code handling and error messages

## Changes Made

### 1. Enhanced AID Support (`nfc_service.dart`)
Added support for more card variants:
```dart
- Visa Platinum: A0000000030000
- Visa V Pay: A0000000032020
- RuPay Credit: A0000005240010
```

### 2. Retry Mechanism
Implemented `_transceiveWithRetry()` method that:
- Retries failed NFC transceive operations up to 3 times
- Uses exponential backoff (100ms, 200ms, 300ms)
- Provides detailed logging for each attempt
- Applied to all critical operations: PPSE, AID selection, GPO, and record reading

### 3. Improved Card Type Detection
Enhanced `_determineCardType()` to better identify:
- RuPay cards with BIN ranges: 6083, 6082, 608, 607, 606, 6522, 6521, 60
- Mastercard 2-series BINs (2221-2720)
- Diners Club cards (36, 38, 39)

### 4. Better Tag Type Handling
- More permissive tag type detection
- Specific handling for MIFARE cards (access cards vs payment cards)
- Clear error messages for unsupported card types

### 5. Enhanced Logging
- Added detailed status word (SW1SW2) logging
- Response length validation
- Better error context in logs

## Testing Instructions

### For Visa Platinum Card (428094...)

1. **Clean the card**: Make sure the NFC chip area is clean
2. **Proper positioning**: 
   - Hold the card flat against the back of your phone
   - The NFC antenna is usually in the center or top of the phone
   - Try different positions if it doesn't work immediately
3. **Keep it steady**: Hold the card still for at least 3-5 seconds
4. **Check logs**: Look for these debug messages:
   ```
   [NFC_DEBUG] NFC tag detected
   [NFC_DEBUG] Trying known AID: Visa Platinum
   [NFC_DEBUG] Application selected successfully
   ```

### For RuPay Debit Card (608332...)

1. **Ensure NFC is enabled**: Check Android NFC settings
2. **Position correctly**: RuPay cards may have NFC chip in different locations
3. **Wait for full scan**: The retry mechanism will attempt multiple times
4. **Check logs**: Look for:
   ```
   [NFC_DEBUG] PPSE selected successfully
   [NFC_DEBUG] AIDs extracted
   [NFC_DEBUG] GPO completed
   [NFC_DEBUG] Card data extracted successfully
   ```

## Common Issues & Solutions

### Issue: "Unsupported card type"
**Solution**: 
- Your card might not have NFC capability
- Try using the camera scan feature instead
- Check if your card has the contactless symbol (((

### Issue: "Card removed too early"
**Solution**:
- Hold the card steady for longer (5-10 seconds)
- Don't move the card during scanning
- Ensure good contact between card and phone

### Issue: "NFC session timeout"
**Solution**:
- The timeout is now 60 seconds
- Try repositioning the card
- Clean both the card and phone back
- Remove any phone case that might interfere

### Issue: "Failed to read card data"
**Solution**:
- The retry mechanism will attempt 3 times automatically
- If it still fails, try:
  - Restarting the app
  - Toggling NFC off and on in phone settings
  - Trying a different location on the phone back

## Debug Logging

To see detailed NFC logs:

1. **Android Studio / VS Code**:
   - Run the app in debug mode
   - Check the console for `[NFC_DEBUG]` messages

2. **Terminal**:
   ```bash
   flutter run
   # or
   adb logcat | grep NFC_DEBUG
   ```

3. **Key Log Points**:
   - `H1`: NFC availability check
   - `H2`: Tag detection
   - `H3`: PPSE selection
   - `H4`: AID selection
   - `H5`: GPO (Get Processing Options)
   - `H6`: Record reading and data extraction

## Card-Specific Notes

### Visa Cards
- Most Visa cards use AID: `A0000000031010`
- Visa Platinum may use: `A0000000030000`
- Visa Electron: `A0000000032010`

### RuPay Cards
- RuPay cards starting with 608, 607, 606 are supported
- **RuPay Domestic (India only) cards**: Now fully supported with proper PDOL handling
- Some RuPay cards may not have NFC enabled
- RuPay cards issued before 2016 might not support contactless
- See `RUPAY_DOMESTIC_FIX.md` for detailed information on RuPay domestic card support

### Mastercard
- Standard AID: `A0000000041010`
- Maestro: `A0000000043060`
- 2-series BINs (2221-2720) are now supported

## Performance Improvements

1. **Faster Detection**: Retry mechanism reduces failed scans
2. **Better Success Rate**: More AIDs = higher compatibility
3. **Clearer Errors**: Users get specific error messages
4. **Longer Timeout**: 60 seconds allows for slower cards

## Next Steps If Issues Persist

1. **Check Card Compatibility**:
   - Not all cards have NFC chips
   - Some banks disable NFC by default
   - Contact your bank to verify NFC is enabled

2. **Phone Compatibility**:
   - Ensure your phone has NFC hardware
   - Check Android version (minimum Android 5.0)
   - Some phones have weaker NFC antennas

3. **Alternative Methods**:
   - Use camera-based card scanning
   - Manual entry of card details
   - Contact support with debug logs

## Technical Details

### NFC Communication Flow
```
1. Poll for NFC tag (60s timeout)
2. Verify tag type (ISO7816/MIFARE DESFire)
3. Select PPSE (Payment System Environment)
4. Extract AIDs from PPSE response
5. Try each AID until one succeeds
6. If PPSE fails, try known AIDs directly
7. Send GPO (Get Processing Options)
8. Read records from AFL (Application File Locator)
9. Extract PAN, expiry, cardholder name
10. Determine card type from BIN
```

### Status Codes
- `9000`: Success
- `6A82`: File/application not found
- `6A81`: Function not supported
- `6985`: Conditions not satisfied
- `6D00`: Instruction not supported

## Support

If you continue to experience issues:
1. Collect debug logs
2. Note the exact error message
3. Provide card BIN (first 6 digits)
4. Specify phone model and Android version

