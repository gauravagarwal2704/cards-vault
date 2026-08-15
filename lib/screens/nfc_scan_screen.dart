import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/nfc_provider.dart';
import '../models/card_data.dart';
import '../services/secure_card_storage.dart';
import 'card_edit_screen.dart';
import '../theme/app_typography.dart';

class NfcScanScreen extends StatefulWidget {
  const NfcScanScreen({super.key});

  @override
  State<NfcScanScreen> createState() => _NfcScanScreenState();
}

class _NfcScanScreenState extends State<NfcScanScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final SecureCardStorage _cardStorage = SecureCardStorage();
  bool _hasStartedScan = false;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startScan();
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_hasStartedScan) return;
    _hasStartedScan = true;

    final nfcProvider = context.read<NfcProvider>();
    nfcProvider.clearError();
    await nfcProvider.readCard();

    if (!mounted) return;

    if (nfcProvider.state == NfcState.success && nfcProvider.cardData != null) {
      _onCardScanned(nfcProvider.cardData!);
    } else if (nfcProvider.state == NfcState.error) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(nfcProvider.errorMessage ?? 'Failed to read card'),
          backgroundColor: Colors.red,
          action: SnackBarAction(
            label: 'Retry',
            textColor: Colors.white,
            onPressed: () {
              _hasStartedScan = false;
              _startScan();
            },
          ),
        ),
      );
    }
  }

  Future<void> _onCardScanned(CardData cardData) async {
    final result = await Navigator.push<CardData>(
      context,
      MaterialPageRoute(
        builder: (context) => CardEditScreen(card: cardData),
      ),
    );

    if (result != null && mounted) {
      try {
        await _cardStorage.saveCard(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Card saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to save card: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1C1C1E),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Consumer<NfcProvider>(
                builder: (context, nfcProvider, child) {
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedBuilder(
                        animation: _pulseAnimation,
                        builder: (context, child) {
                          return Transform.scale(
                            scale: nfcProvider.state == NfcState.scanning
                                ? _pulseAnimation.value
                                : 1.0,
                            child: Container(
                              width: 140,
                              height: 140,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: const Color(0xFF0EA5E9).withOpacity(0.15),
                                border: Border.all(
                                  color: const Color(0xFF0EA5E9).withOpacity(0.3),
                                  width: 2,
                                ),
                              ),
                              child: const Icon(
                                Icons.contactless,
                                size: 70,
                                color: Color(0xFF0EA5E9),
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 40),
                      Text(
                        nfcProvider.state == NfcState.scanning
                            ? 'Scanning...'
                            : nfcProvider.state == NfcState.success
                                ? 'Card Read!'
                                : 'Hold Card Near',
                        style: AppTypography.display(
                          fontSize: 28,
                          color: Colors.white,
                        ).copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        nfcProvider.state == NfcState.scanning
                            ? 'Keep your card steady'
                            : 'Place your card at the back of your phone',
                        style: AppTypography.bodyLarge(color: Colors.white60),
                        textAlign: TextAlign.center,
                      ),
                      if (nfcProvider.state == NfcState.error) ...[
                        const SizedBox(height: 32),
                        ElevatedButton(
                          onPressed: () {
                            _hasStartedScan = false;
                            _startScan();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0EA5E9),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 32,
                              vertical: 14,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Text(
                            'Try Again',
                            style: AppTypography.button(
                              fontSize: 16,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Colors.white38,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Make sure NFC is enabled in your device settings',
                        style: AppTypography.label(
                          color: Colors.white38,
                        ).copyWith(fontWeight: FontWeight.w400),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

