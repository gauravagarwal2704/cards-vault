import 'dart:io';
import 'dart:async';
import 'package:app_settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/nfc_provider.dart';
import '../providers/camera_provider.dart';
import '../models/card_data.dart';
import '../services/auth_service.dart';
import '../services/secure_card_storage.dart';
import '../utils/nfc_availability_prompt.dart';
import 'card_edit_screen.dart';

class AddCardScreen extends StatefulWidget {
  const AddCardScreen({super.key});

  @override
  State<AddCardScreen> createState() => _AddCardScreenState();
}

class _AddCardScreenState extends State<AddCardScreen> {
  bool _isCardNumberVisible = false;
  bool _isExpiryVisible = false;
  Timer? _hideTimer;
  final AuthService _authService = AuthService();
  final SecureCardStorage _cardStorage = SecureCardStorage();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NfcProvider>().checkNfcAvailability();
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 30), () {
      if (mounted) {
        setState(() {
          _isCardNumberVisible = false;
          _isExpiryVisible = false;
        });
      }
    });
  }

  Future<void> _toggleCardNumberVisibility(CardData cardData) async {
    if (_isCardNumberVisible) {
      setState(() {
        _isCardNumberVisible = false;
        _hideTimer?.cancel();
      });
    } else {
      final authenticated = await _authService.authenticateForCardDetails();
      if (authenticated && mounted) {
        setState(() {
          _isCardNumberVisible = true;
        });
        _startHideTimer();
      }
    }
  }

  Future<void> _toggleExpiryVisibility(CardData cardData) async {
    if (_isExpiryVisible) {
      setState(() {
        _isExpiryVisible = false;
        _hideTimer?.cancel();
      });
    } else {
      final authenticated = await _authService.authenticateForCardDetails();
      if (authenticated && mounted) {
        setState(() {
          _isExpiryVisible = true;
        });
        _startHideTimer();
      }
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$label copied to clipboard'),
          duration: const Duration(seconds: 2),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Add Card'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: Consumer2<NfcProvider, CameraProvider>(
        builder: (context, nfcProvider, cameraProvider, child) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (Platform.isIOS)
                    _buildIOSWarningCard()
                  else if (!nfcProvider.isNfcEnabled &&
                      nfcProvider.state != NfcState.checking)
                    _buildNfcUnavailableCard(nfcProvider.isNfcSupported),
                  
                  const SizedBox(height: 24),
                  
                  Expanded(
                    child: _buildMainContent(context, nfcProvider),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  _buildActionButton(context, nfcProvider, cameraProvider),
                  
                  const SizedBox(height: 16),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildIOSWarningCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, color: Colors.orange.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'NFC Card reading not supported on iOS, please use Camera',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNfcUnavailableCard(bool isSupported) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.nfc_outlined, color: Colors.red.shade700, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isSupported
                  ? 'NFC is turned off. Turn it on in settings to tap and scan.'
                  : 'This device does not have NFC hardware.',
              style: TextStyle(
                color: Colors.red.shade900,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (isSupported)
            TextButton(
              onPressed: () => AppSettings.openAppSettings(
                type: AppSettingsType.nfc,
              ),
              child: const Text('Turn on'),
            ),
        ],
      ),
    );
  }

  Widget _buildMainContent(BuildContext context, NfcProvider nfcProvider) {
    Widget content;
    if (nfcProvider.state == NfcState.success && nfcProvider.cardData != null) {
      content = _buildCardPreview(nfcProvider.cardData!);
    } else if (nfcProvider.state == NfcState.scanning) {
      content = _buildScanningState();
    } else {
      content = _buildIdleState();
    }
    
    return SingleChildScrollView(
      child: content,
    );
  }

  Widget _buildIdleState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.nfc,
              size: 60,
              color: Colors.blue.shade600,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Ready to Scan',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Tap the button below and hold your\ncard near the device',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                const SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
                Icon(
                  Icons.nfc,
                  size: 60,
                  color: Colors.blue.shade600,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Scanning...',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Hold your card near the device\nand keep it steady',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 16,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCardPreview(CardData cardData) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxWidth: 400),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: _getCardGradient(cardData.cardType),
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Icon(
                      Icons.credit_card,
                      color: Colors.white,
                      size: 32,
                    ),
                    Text(
                      cardData.cardType,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 40),
                Row(
                  children: [
                    Expanded(
                      child: FutureBuilder<String>(
                        future: _isCardNumberVisible 
                            ? cardData.getFormattedCardNumber()
                            : Future.value(cardData.maskedCardNumber),
                        builder: (context, snapshot) {
                          return Text(
                            snapshot.data ?? cardData.maskedCardNumber,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 2,
                            ),
                          );
                        },
                      ),
                    ),
                    IconButton(
                      onPressed: () => _toggleCardNumberVisibility(cardData),
                      icon: Icon(
                        _isCardNumberVisible ? Icons.visibility_off : Icons.visibility,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    if (_isCardNumberVisible)
                      IconButton(
                        onPressed: () async {
                          final cardNumber = await cardData.getDecryptedCardNumber();
                          _copyToClipboard(cardNumber, 'Card number');
                        },
                        icon: const Icon(
                          Icons.copy,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    FutureBuilder<String?>(
                      future: cardData.getDecryptedCardholderName(),
                      builder: (context, snapshot) {
                        if (snapshot.hasData && snapshot.data != null) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'CARDHOLDER',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                snapshot.data!,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'EXPIRES',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FutureBuilder<String>(
                              future: _isExpiryVisible 
                                  ? cardData.getDecryptedExpiryDate()
                                  : Future.value('**/**'),
                              builder: (context, snapshot) {
                                return Text(
                                  snapshot.data ?? '**/**',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                  ),
                                );
                              },
                            ),
                            IconButton(
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () => _toggleExpiryVisibility(cardData),
                              icon: Icon(
                                _isExpiryVisible ? Icons.visibility_off : Icons.visibility,
                                color: Colors.white,
                                size: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Card read successfully!',
                  style: TextStyle(
                    color: Colors.green.shade900,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildCardDetails(cardData),
        ],
      ),
    );
  }

  Widget _buildCardDetails(CardData cardData) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 400),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Card Information',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 16),
          _buildDetailRowWithVisibility(
            icon: Icons.credit_card,
            label: 'Card Number',
            cardData: cardData,
            isVisible: _isCardNumberVisible,
            onToggle: () => _toggleCardNumberVisibility(cardData),
            getFutureValue: () => cardData.getFormattedCardNumber(),
            maskedValue: cardData.maskedCardNumber,
            iconColor: Colors.blue,
          ),
          const Divider(height: 24),
          _buildDetailRowWithVisibility(
            icon: Icons.calendar_today,
            label: 'Expiry Date',
            cardData: cardData,
            isVisible: _isExpiryVisible,
            onToggle: () => _toggleExpiryVisibility(cardData),
            getFutureValue: () => cardData.getDecryptedExpiryDate(),
            maskedValue: '**/**',
            iconColor: Colors.orange,
          ),
          const Divider(height: 24),
          _buildDetailRow(
            icon: Icons.account_balance,
            label: 'Card Type',
            value: cardData.cardType,
            iconColor: Colors.purple,
          ),
          FutureBuilder<String?>(
            future: cardData.getDecryptedCardholderName(),
            builder: (context, snapshot) {
              if (snapshot.hasData && snapshot.data != null) {
                return Column(
                  children: [
                    const Divider(height: 24),
                    _buildDetailRow(
                      icon: Icons.person,
                      label: 'Cardholder Name',
                      value: snapshot.data!,
                      iconColor: Colors.green,
                    ),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
          ),
          const Divider(height: 24),
          _buildDetailRow(
            icon: cardData.readMethod == ReadMethod.camera ? Icons.camera_alt : Icons.nfc,
            label: 'Read Method',
            value: cardData.readMethod == ReadMethod.camera ? 'Camera OCR' : 'NFC Contactless',
            iconColor: Colors.teal,
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'CVV cannot be read via NFC for security reasons',
                    style: TextStyle(
                      color: Colors.blue.shade900,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 16,
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDetailRowWithVisibility({
    required IconData icon,
    required String label,
    required CardData cardData,
    required bool isVisible,
    required VoidCallback onToggle,
    required Future<String> Function() getFutureValue,
    required String maskedValue,
    required Color iconColor,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor, size: 20),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 4),
              FutureBuilder<String>(
                future: isVisible ? getFutureValue() : Future.value(maskedValue),
                builder: (context, snapshot) {
                  return Text(
                    snapshot.data ?? maskedValue,
                    style: const TextStyle(
                      fontSize: 16,
                      color: Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onToggle,
          icon: Icon(
            isVisible ? Icons.visibility_off : Icons.visibility,
            color: iconColor,
            size: 20,
          ),
        ),
        if (isVisible)
          IconButton(
            onPressed: () async {
              final value = await getFutureValue();
              _copyToClipboard(value, label);
            },
            icon: Icon(
              Icons.copy,
              color: iconColor,
              size: 18,
            ),
          ),
      ],
    );
  }

  List<Color> _getCardGradient(String cardType) {
    switch (cardType.toLowerCase()) {
      case 'visa':
        return [const Color(0xFF1A1F71), const Color(0xFF0066B2)];
      case 'mastercard':
        return [const Color(0xFFEB001B), const Color(0xFFF79E1B)];
      case 'american express':
        return [const Color(0xFF006FCF), const Color(0xFF00A3E0)];
      case 'discover':
        return [const Color(0xFFFF6000), const Color(0xFFFF9900)];
      default:
        return [const Color(0xFF434343), const Color(0xFF000000)];
    }
  }

  Widget _buildActionButton(BuildContext context, NfcProvider nfcProvider, CameraProvider cameraProvider) {
    if (nfcProvider.state == NfcState.success) {
      return Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () {
                nfcProvider.reset();
              },
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                side: const BorderSide(color: Colors.blue, width: 2),
              ),
              child: const Text(
                'Scan Another',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: () async {
                try {
                  final cardData = nfcProvider.cardData;
                  if (cardData != null) {
                    await _cardStorage.saveCard(cardData);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Card saved successfully!'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to save card: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.blue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Save Card',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ),
          ),
        ],
      );
    }

    // The NFC button stays enabled even when NFC is off or missing; tapping it
    // then explains what to do instead of the option disappearing.
    bool canScanNfc = nfcProvider.state != NfcState.scanning &&
                      cameraProvider.state != CameraState.capturing &&
                      cameraProvider.state != CameraState.processing;

    bool canScanCamera = cameraProvider.state != CameraState.capturing &&
                         cameraProvider.state != CameraState.validating &&
                         cameraProvider.state != CameraState.processing &&
                         nfcProvider.state != NfcState.scanning;

    return Column(
      children: [
        ElevatedButton(
            onPressed: canScanNfc
                ? () async {
                    final nfcReady = await ensureNfcReady(context);
                    if (!context.mounted || !nfcReady) return;

                    nfcProvider.clearError();
                    await nfcProvider.readCard();
                    
                    if (nfcProvider.state == NfcState.error && 
                        nfcProvider.errorMessage != null &&
                        context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(nfcProvider.errorMessage!),
                          backgroundColor: Colors.red,
                          duration: const Duration(seconds: 4),
                          action: SnackBarAction(
                            label: 'Dismiss',
                            textColor: Colors.white,
                            onPressed: () {},
                          ),
                        ),
                      );
                    }
                  }
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              backgroundColor: Colors.blue,
              disabledBackgroundColor: Colors.grey.shade300,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: canScanNfc ? 2 : 0,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (nfcProvider.state == NfcState.scanning)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                else
                  const Icon(Icons.nfc, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Text(
                  nfcProvider.state == NfcState.scanning
                      ? 'Scanning NFC...'
                      : 'Scan with NFC',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 12),
        ElevatedButton(
          onPressed: canScanCamera
              ? () async {
                  cameraProvider.clearError();
                  await cameraProvider.captureAndProcessCard(context);
                  
                  if (cameraProvider.state == CameraState.success && 
                      cameraProvider.ocrResult != null &&
                      context.mounted) {
                    final CardData? result = await Navigator.push<CardData>(
                      context,
                      MaterialPageRoute(
                        builder: (context) => CardEditScreen(
                          ocrResult: cameraProvider.ocrResult!,
                        ),
                      ),
                    );
                    
                    if (result != null && context.mounted) {
                      nfcProvider.setCardDataFromCamera(result);
                    } else {
                      cameraProvider.reset();
                    }
                  } else if (cameraProvider.state == CameraState.error && 
                             cameraProvider.errorMessage != null &&
                             context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(cameraProvider.errorMessage!),
                        backgroundColor: Colors.red,
                        duration: const Duration(seconds: 5),
                        action: SnackBarAction(
                          label: 'Retry',
                          textColor: Colors.white,
                          onPressed: () {
                            cameraProvider.clearError();
                          },
                        ),
                      ),
                    );
                  }
                }
              : null,
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 18),
            backgroundColor: Colors.green,
            disabledBackgroundColor: Colors.grey.shade300,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            elevation: canScanCamera ? 2 : 0,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (cameraProvider.state == CameraState.capturing || 
                  cameraProvider.state == CameraState.validating ||
                  cameraProvider.state == CameraState.processing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              else
                const Icon(Icons.camera_alt, color: Colors.white, size: 24),
              const SizedBox(width: 12),
              Text(
                cameraProvider.state == CameraState.capturing
                    ? 'Opening Camera...'
                    : cameraProvider.state == CameraState.validating
                        ? 'Validating...'
                        : cameraProvider.state == CameraState.processing
                            ? 'Processing...'
                            : 'Scan with Camera',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

