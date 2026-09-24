import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/card_data.dart';
import '../providers/nfc_provider.dart';
import '../services/secure_card_storage.dart';
import '../services/app_log_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_motion.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_design_system.dart';
import 'card_edit_screen.dart';

class NfcScanScreen extends StatefulWidget {
  const NfcScanScreen({super.key});

  @override
  State<NfcScanScreen> createState() => _NfcScanScreenState();
}

class _NfcScanScreenState extends State<NfcScanScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  final SecureCardStorage _cardStorage = SecureCardStorage();
  bool _hasStartedScan = false;
  bool _motionConfigured = false;

  @override
  void initState() {
    super.initState();
    AppLogService.instance.action('Navigation', 'Opened NFC card scan');
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _startScan());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionConfigured) return;
    _motionConfigured = true;
    if (AppMotion.reduceMotion(context)) {
      _pulseController.stop();
      _pulseController.value = 0;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _startScan() async {
    if (_hasStartedScan) return;
    _hasStartedScan = true;
    AppLogService.instance.action('Scanning', 'NFC scan started');
    final provider = context.read<NfcProvider>();
    provider.clearError();
    await provider.readCard();
    if (!mounted) return;

    if (provider.state == NfcState.success && provider.cardData != null) {
      AppLogService.instance.action('Scanning', 'NFC scan succeeded');
      HapticFeedback.mediumImpact();
      await _reviewCard(provider.cardData!);
    } else if (provider.state == NfcState.error) {
      AppLogService.instance.action('Scanning', 'NFC scan failed');
      HapticFeedback.heavyImpact();
    }
  }

  Future<void> _retry() async {
    _hasStartedScan = false;
    await _startScan();
  }

  Future<void> _reviewCard(CardData card) async {
    final result = await Navigator.push<CardData>(
      context,
      MaterialPageRoute(builder: (_) => CardEditScreen(card: card)),
    );
    if (result == null || !mounted) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      await _cardStorage.saveCard(result);
      AppLogService.instance.action('Cards', 'NFC card saved');
      if (!mounted) return;
      HapticFeedback.mediumImpact();
      Navigator.pop(context, true);
    } catch (error) {
      AppLogService.instance.record('Cards', 'NFC card save failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save the card: $error'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tap card'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: SafeArea(
        child: Consumer<NfcProvider>(
          builder: (context, provider, _) {
            final error = provider.state == NfcState.error;
            final success = provider.state == NfcState.success;
            final title = error
                ? 'Card not read'
                : success
                ? 'Card read'
                : provider.state == NfcState.checking
                ? 'Getting ready'
                : 'Hold card near phone';
            final message = error
                ? provider.errorMessage ?? 'Move the card and try again.'
                : success
                ? 'Opening review…'
                : 'Keep the card still against the back of your device.';

            return LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: Column(
                      children: [
                        _ProgressSteps(
                          currentStep: success
                              ? 2
                              : error
                              ? 0
                              : 1,
                        ),
                        SizedBox(height: constraints.maxHeight < 600 ? 32 : 72),
                        Semantics(
                          liveRegion: true,
                          label: '$title. $message',
                          child: AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, _) => Transform.scale(
                              scale: !error && !success
                                  ? _pulseAnimation.value
                                  : 1,
                              child: Container(
                                width: 168,
                                height: 168,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: error
                                      ? scheme.errorContainer
                                      : success
                                      ? AppSemanticColors.of(context)
                                            .successContainer
                                      : scheme.primaryContainer,
                                ),
                                child: Icon(
                                  error
                                      ? Icons.nfc_rounded
                                      : success
                                      ? Icons.check_rounded
                                      : Icons.contactless_rounded,
                                  size: 76,
                                  color: error
                                      ? scheme.onErrorContainer
                                      : success
                                      ? AppSemanticColors.of(context)
                                            .onSuccessContainer
                                      : scheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxl),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                        if (error) ...[
                          const SizedBox(height: AppSpacing.xl),
                          FilledButton.icon(
                            onPressed: _retry,
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('Try again'),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xxl),
                        AppStatusMessage(
                          kind: AppStatusKind.info,
                          message: 'The NFC antenna is usually near the top or center of the back of your phone.',
                          icon: Icons.lightbulb_outline_rounded,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ProgressSteps extends StatelessWidget {
  const _ProgressSteps({required this.currentStep});

  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    const labels = ['Ready', 'Reading', 'Review'];
    return Semantics(
      label:
          'Step ${currentStep + 1} of ${labels.length}: ${labels[currentStep]}',
      child: Row(
        children: [
          for (var index = 0; index < labels.length; index++) ...[
            if (index > 0)
              Expanded(
                child: Divider(
                  color: index <= currentStep
                      ? scheme.primary
                      : scheme.outlineVariant,
                  thickness: 2,
                ),
              ),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: index <= currentStep
                    ? scheme.primaryContainer
                    : scheme.surfaceContainerHigh,
                borderRadius: AppShapes.pillRadius,
              ),
              child: Text(
                labels[index],
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: index <= currentStep
                      ? scheme.onPrimaryContainer
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
