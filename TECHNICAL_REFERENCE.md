# Technical Reference - NFC EMV Card Reading

## APDU Commands Reference

### 1. SELECT PPSE (Payment System Environment)

**Command**: `00A404000E325041592E5359532E444446303100`

**Breakdown**:
- `00` - CLA (Class byte)
- `A4` - INS (Instruction: SELECT)
- `04` - P1 (Select by name)
- `00` - P2 (First or only occurrence)
- `0E` - Lc (Length: 14 bytes)
- `325041592E5359532E444446303100` - Data: "2PAY.SYS.DDF01" in hex
- `00` - Le (Expected response length)

**Response**: FCI Template containing list of AIDs (Application IDs)

### 2. SELECT AID (Application ID)

**Command Template**: `00A4040007{AID}00`

**Example** (Visa): `00A4040007A000000003101000`

**Breakdown**:
- `00` - CLA
- `A4` - INS (SELECT)
- `04` - P1 (Select by name)
- `00` - P2
- `07` - Lc (Length varies by AID, 7 bytes in this example)
- `A0000000031010` - Application ID (Visa)
- `00` - Le (Expected response length - REQUIRED for strict cards)

**Response**: FCI Template with application details

**Important**: The Le byte (`00`) at the end is **required** for domestic cards and strict EMV implementations. Some international cards work without it, but domestic-only cards (like Axis Bank Priority Debit) require full ISO 7816-4 compliance.

### 3. GET PROCESSING OPTIONS (GPO)

**Command**: `80A800000283000000`

**Breakdown**:
- `80` - CLA (Proprietary class)
- `A8` - INS (GET PROCESSING OPTIONS)
- `00` - P1
- `00` - P2
- `02` - Lc (2 bytes of data)
- `8300` - PDOL (Processing Options Data Object List) - empty PDOL
- `00` - Le (Expected response length - REQUIRED for strict cards)

**With PDOL Data**: `80A80000{LENGTH}83{PDOL_LENGTH}{PDOL_DATA}00`

**Response**: AFL (Application File Locator) - tells which records to read

**Important**: The Le byte (`00`) at the end is **required** for strict EMV implementations. Cards that require full ISO 7816-4 compliance will return error `6700` (Wrong length) without it.

### 4. READ RECORD

**Command Template**: `00B2{RECORD}{SFI}00`

**Example**: `00B2010C00` (Read record 1 from SFI 1)

**Breakdown**:
- `00` - CLA
- `B2` - INS (READ RECORD)
- `{RECORD}` - Record number (e.g., 01, 02, 03)
- `{SFI}` - Short File Identifier shifted left 3 bits + 0x04 (e.g., 0C for SFI 1)
- `00` - Le (Expected response length - REQUIRED for strict cards)

**Response**: Record data containing card information

**Important**: All APDU commands must include the Le byte for maximum compatibility.

## EMV Tags Reference

### Card Data Tags

| Tag | Name | Description | Format |
|-----|------|-------------|--------|
| `5A` | PAN | Primary Account Number (Card Number) | BCD, up to 19 digits |
| `5F24` | Expiry Date | Card expiration date | YYMMDD |
| `5F20` | Cardholder Name | Name on card | ASCII |
| `57` | Track 2 Equivalent | Magnetic stripe Track 2 data | BCD with separator 'D' |
| `9F42` | Currency Code | Transaction currency | Numeric |
| `5F34` | PAN Sequence Number | Card sequence number | Numeric |

### Response Tags

| Tag | Name | Description |
|-----|------|-------------|
| `6F` | FCI Template | File Control Information |
| `A5` | FCI Proprietary Template | Issuer-specific data |
| `BF0C` | FCI Issuer Discretionary Data | Application list |
| `61` | Application Template | Application entry |
| `4F` | ADF Name (AID) | Application Identifier |
| `87` | Application Priority Indicator | Selection priority |
| `94` | AFL | Application File Locator |
| `77` | Response Message Template Format 2 | Alternative GPO response |

## Status Words (SW1SW2)

| Code | Meaning | Common Cause |
|------|---------|--------------|
| `9000` | Success | Command executed successfully |
| `6283` | Selected file invalidated | File deactivated |
| `6700` | Wrong length (Lc and/or Le) | **Missing Le byte** - Add `00` at end of command |
| `6982` | Security status not satisfied | Authentication required |
| `6985` | Conditions of use not satisfied | Card blocked or restricted |
| `6A82` | File not found | Invalid AID or record |
| `6A86` | Incorrect P1 P2 | Wrong parameters |

**Important**: Error `6700` is commonly seen with domestic cards that require strict ISO 7816-4 compliance. Always include the Le byte (`00`) at the end of all APDU commands.

## BER-TLV Encoding

### Tag Format
- **1 byte**: If bits 1-5 are not all 1s
- **2+ bytes**: If bits 1-5 are all 1s (extended tag)

### Length Format
- **Short form** (0-127): Single byte, bit 8 = 0
- **Long form** (128+): First byte has bit 8 = 1, bits 1-7 indicate number of subsequent length bytes

### Example TLV Parsing

```
5A 08 4532123456789012
```

- **Tag**: `5A` (PAN)
- **Length**: `08` (8 bytes)
- **Value**: `4532123456789012` (Card number in BCD)

## AFL (Application File Locator) Structure

AFL is returned by GPO and consists of 4-byte entries:

```
[SFI][First Record][Last Record][Offline Auth Records]
```

**Example**: `08 01 03 00`
- SFI: `08` (shifted right 3 bits = 1)
- First Record: `01`
- Last Record: `03`
- Offline Auth Records: `00`

This means: Read records 1-3 from SFI 1

## Card Type Detection

### By PAN Prefix (Priority Order)

| IIN Range | Card Type | Example | Priority |
|-----------|-----------|---------|----------|
| 4 | Visa | 4532... | High |
| 51-55 | Mastercard | 5425... | High |
| 34, 37 | American Express | 3782... | High |
| 6011 | Discover | 6011... | Highest (4-digit) |
| 6522, 6521 | RuPay | 6522... | Highest (4-digit) |
| 608, 607, 606 | RuPay | 6081... | High (3-digit) |
| 65 | Discover | 6500... | Medium (2-digit) |
| 60 | RuPay | 6000... | Low (2-digit) |
| 35 | JCB | 3566... | Medium |
| 62 | UnionPay | 6212... | Medium |

**Note**: Detection uses priority-based matching to avoid conflicts. More specific prefixes (4-digit) are checked before generic ones (2-digit).

### By AID (Known Payment AIDs)

| AID | Card Type | Variant |
|-----|-----------|---------|
| A0000000031010 | Visa | Credit/Debit (Standard) |
| A0000000032010 | Visa | Electron |
| A0000000033010 | Visa | Interlink |
| A0000000038010 | Visa | Plus |
| A0000000041010 | Mastercard | Credit/Debit (Standard) |
| A0000000043060 | Maestro | Debit |
| A00000000410101213 | Mastercard | Debit |
| A00000000410101215 | Mastercard | Credit |
| A0000005241010 | RuPay | Standard |
| A000000524 | RuPay | Domestic |

**Multiple AID Strategy**: The app tries all AIDs from PPSE first, then falls back to these known AIDs for maximum compatibility.

## Security Notes

### What CAN Be Read
- ✅ Card Number (PAN)
- ✅ Expiry Date
- ✅ Cardholder Name (if present)
- ✅ Card Type
- ✅ Application Version
- ✅ Transaction Counter

### What CANNOT Be Read
- ❌ CVV/CVC (not stored on chip)
- ❌ PIN (never stored)
- ❌ Full magnetic stripe data
- ❌ Card verification values for online transactions

### Encryption Requirements

**Critical**: All extracted card data must be encrypted immediately:

```dart
// After extracting PAN
String pan = extractedPAN;
// TODO: ENCRYPT THIS DATA IMMEDIATELY
String encryptedPAN = await encryptionService.encrypt(pan);
```

**Recommended**: Use AES-256 encryption with secure key storage

## Common Issues & Solutions

### Issue: Error 6700 (Wrong Length)
**Cause**: Missing Le byte in APDU command
**Solution**: Add `00` at the end of all APDU commands (SELECT AID, GPO, READ RECORD)
**Example**: Change `00A4040007A0000000031010` to `00A4040007A000000003101000`

### Issue: PPSE Selection Fails
**Cause**: Card may not support PPSE or is domestic-only
**Solution**: App automatically falls back to known payment AIDs

### Issue: All AIDs Fail
**Cause**: Card uses non-standard AID or is not EMV-compliant
**Solution**: Card may not be supported for contactless reading

### Issue: Domestic Cards Not Working
**Cause**: Domestic cards require strict ISO 7816-4 compliance
**Solution**: Ensure all APDU commands include Le byte (`00`)

### Issue: International Cards Work but Domestic Don't
**Cause**: International cards are lenient, domestic cards are strict
**Solution**: Use proper APDU format with Le byte for all commands

### Issue: GPO Returns 6985
**Cause**: Card requires additional authentication or PDOL data
**Solution**: Build proper PDOL data based on card requirements

### Issue: PAN Not in Records
**Cause**: PAN may be in Track 2 Equivalent instead of tag 5A
**Solution**: Check Track 2 Equivalent (tag 57) as fallback

### Issue: Parsing Errors
**Cause**: Some cards use non-standard TLV encoding
**Solution**: Implement robust TLV parser with error handling

## Domestic vs International Cards

### Key Differences

| Aspect | International Cards | Domestic Cards |
|--------|-------------------|----------------|
| **PPSE Support** | Full support | May be limited or absent |
| **APDU Strictness** | Lenient (Le byte optional) | Strict (Le byte required) |
| **Error Handling** | Forgiving | Returns 6700 if format wrong |
| **AID Variants** | Standard AIDs | May use alternative AIDs |
| **Example** | HDFC International Debit | Axis Bank Priority Debit |

### Best Practices for Compatibility

1. **Always include Le byte** (`00`) in all APDU commands
2. **Extract all AIDs** from PPSE, not just the first one
3. **Try each AID sequentially** until one succeeds
4. **Implement fallback** to known payment AIDs
5. **Handle PPSE failures** gracefully
6. **Follow ISO 7816-4 strictly** for maximum compatibility

## Testing Commands

### Manual APDU Testing

You can test APDU commands using the NFC service:

```dart
// Test PPSE selection
String response = await FlutterNfcKit.transceive(
  "00A404000E325041592E5359532E444446303100"
);
print("PPSE Response: $response");

// Test AID selection (Visa)
String aidResponse = await FlutterNfcKit.transceive(
  "00A404000EA0000000031010"
);
print("AID Response: $aidResponse");
```

## Performance Considerations

- **Typical Read Time**: 3-10 seconds
- **NFC Range**: < 4cm (very short)
- **Session Timeout**: 30 seconds (configurable)
- **Retry Strategy**: Implement exponential backoff

## Compliance Requirements

### PCI DSS
- Encrypt all card data at rest
- Use TLS for data in transit
- Implement access controls
- Log all card data access
- Regular security audits

### Card Network Rules
- Do not store CVV/CVC
- Mask PAN in logs
- Implement tokenization
- Follow EMV specifications

## References

- EMVCo Specifications: https://www.emvco.com/
- ISO/IEC 7816: Smart card standards
- ISO/IEC 14443: Contactless card standards
- PCI DSS: https://www.pcisecuritystandards.org/

---

**Note**: This is a technical reference for development purposes. Always ensure compliance with payment card industry standards in production.

