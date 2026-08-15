import 'package:flutter/material.dart';
import 'add_card_screen.dart';
import 'saved_cards_screen.dart';
import '../services/secure_card_storage.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final SecureCardStorage _cardStorage = SecureCardStorage();
  int _cardCount = 0;

  @override
  void initState() {
    super.initState();
    _loadCardCount();
  }

  Future<void> _loadCardCount() async {
    final count = await _cardStorage.getCardCount();
    setState(() {
      _cardCount = count;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Cards Wallet'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 40),
              const Icon(
                Icons.account_balance_wallet,
                size: 80,
                color: Colors.blue,
              ),
              const SizedBox(height: 24),
              const Text(
                'Welcome to Cards Wallet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Securely store and manage your payment cards',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 60),
              _buildMenuCard(
                icon: Icons.nfc,
                title: 'Add New Card',
                subtitle: 'Scan a card using NFC',
                color: Colors.blue,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const AddCardScreen()),
                  );
                  _loadCardCount();
                },
              ),
              const SizedBox(height: 16),
              _buildMenuCard(
                icon: Icons.credit_card,
                title: 'Saved Cards',
                subtitle: '$_cardCount card${_cardCount != 1 ? 's' : ''} saved',
                color: Colors.green,
                onTap: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const SavedCardsScreen()),
                  );
                  _loadCardCount();
                },
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.security, color: Colors.blue.shade700, size: 24),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'All card data is encrypted and stored securely on your device',
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
        ),
      ),
    );
  }

  Widget _buildMenuCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 32),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: Colors.grey.shade400,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

