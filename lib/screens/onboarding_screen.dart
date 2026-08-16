import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/profile_provider.dart';
import '../theme/app_motion.dart';
import '../theme/app_typography.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  final _nameController = TextEditingController();
  final _focusNode = FocusNode();
  late final AnimationController _controller;
  Timer? _focusTimer;
  bool _motionConfigured = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.emphasized,
    )..forward();
    _focusTimer = Timer(const Duration(milliseconds: 520), () {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionConfigured) return;
    _motionConfigured = true;
    if (AppMotion.reduceMotion(context)) {
      _controller.value = 1;
      _focusTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusTimer?.cancel();
    _nameController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _continue() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isSaving) return;

    setState(() => _isSaving = true);
    HapticFeedback.lightImpact();
    await context.read<ProfileProvider>().setDisplayName(name);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final value = Curves.easeOutCubic.transform(_controller.value);
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, 24 * (1 - value)),
                  child: child,
                ),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Hero(
                  tag: 'cardvault-mark',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.asset(
                      'assets/branding/cardvault_icon.png',
                      width: 88,
                      height: 88,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  'Welcome to\nCardVault',
                  style: AppTypography.display(
                    color: colors.onSurface,
                    fontSize: 42,
                  ).copyWith(height: 1.04),
                ),
                const SizedBox(height: 14),
                Text(
                  'Your cards, organised and protected on this device.',
                  style: AppTypography.bodyLarge(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                const Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _PromiseChip(
                      icon: Icons.enhanced_encryption_outlined,
                      label: 'Encrypted',
                    ),
                    _PromiseChip(
                      icon: Icons.phonelink_lock_outlined,
                      label: 'On-device',
                    ),
                    _PromiseChip(
                      icon: Icons.fingerprint_rounded,
                      label: 'Biometric',
                    ),
                  ],
                ),
                const SizedBox(height: 36),
                TextField(
                  key: const ValueKey('onboarding-name-field'),
                  controller: _nameController,
                  focusNode: _focusNode,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  maxLength: 40,
                  onSubmitted: (_) => _continue(),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'What should we call you?',
                    hintText: 'Your name',
                    prefixIcon: Icon(Icons.person_outline),
                    counterText: '',
                  ),
                ),
                const SizedBox(height: 16),
                PressableScale(
                  child: SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton.icon(
                      key: const ValueKey('onboarding-continue'),
                      onPressed:
                          _nameController.text.trim().isEmpty || _isSaving
                          ? null
                          : _continue,
                      icon: AnimatedSwitcher(
                        duration: AppMotion.resolve(context, AppMotion.quick),
                        child: _isSaving
                            ? const SizedBox(
                                key: ValueKey('saving'),
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.arrow_forward_rounded,
                                key: ValueKey('arrow'),
                              ),
                      ),
                      label: const Text('Continue'),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: Text(
                    'Your name stays on this device.',
                    style: AppTypography.caption(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PromiseChip extends StatelessWidget {
  const _PromiseChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Chip(
      avatar: Icon(icon, size: 18, color: scheme.onSecondaryContainer),
      label: Text(label),
      backgroundColor: scheme.secondaryContainer,
      side: BorderSide.none,
    );
  }
}

class CardVaultSplashScreen extends StatefulWidget {
  const CardVaultSplashScreen({super.key});

  @override
  State<CardVaultSplashScreen> createState() => _CardVaultSplashScreenState();
}

class _CardVaultSplashScreenState extends State<CardVaultSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.emphasized,
  )..forward();
  bool _motionConfigured = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_motionConfigured) return;
    _motionConfigured = true;
    if (AppMotion.reduceMotion(context)) _controller.value = 1;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final curved = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.enterCurve,
    );

    return Scaffold(
      backgroundColor: colors.surface,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 0.86, end: 1).animate(curved),
              child: FadeTransition(
                opacity: _controller,
                child: Hero(
                  tag: 'cardvault-mark',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(30),
                    child: Image.asset(
                      'assets/branding/cardvault_icon.png',
                      width: 124,
                      height: 124,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            FadeTransition(
              opacity: CurvedAnimation(
                parent: _controller,
                curve: const Interval(0.35, 1, curve: Curves.easeOut),
              ),
              child: Text(
                'CardVault',
                style: AppTypography.display(
                  color: colors.onSurface,
                  fontSize: 34,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
