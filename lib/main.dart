import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/nfc_provider.dart';
import 'providers/camera_provider.dart';
import 'providers/card_view_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/app_lock_provider.dart';
import 'providers/profile_provider.dart';
import 'screens/onboarding_screen.dart';
import 'screens/saved_cards_screen.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppLockProvider()),
        ChangeNotifierProvider(create: (_) => NfcProvider()),
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        ChangeNotifierProvider(create: (_) => CardViewProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
      ],
      child: Consumer2<ThemeProvider, AppLockProvider>(
        builder: (context, themeProvider, appLockProvider, child) {
          return MaterialApp(
            title: 'CardVault',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.lightTheme,
            darkTheme: themeProvider.materialDarkTheme,
            themeMode: themeProvider.materialThemeMode,
            themeAnimationDuration: AppMotion.standard,
            themeAnimationCurve: AppMotion.standardCurve,
            builder: (context, child) {
              final theme = Theme.of(context);
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: AppTheme.systemOverlayStyle(
                  brightness: theme.colorScheme.brightness,
                  navigationBarColor: theme.scaffoldBackgroundColor,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            },
            home: const _AppEntry(),
          );
        },
      ),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry();

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool _splashElapsed = false;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(milliseconds: 1350), () {
      if (mounted) setState(() => _splashElapsed = true);
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final ready = _splashElapsed && profile.isInitialized;

    return AnimatedSwitcher(
      duration: AppMotion.resolve(context, AppMotion.emphasized),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
          child: child,
        ),
      ),
      child: !ready
          ? const CardVaultSplashScreen(key: ValueKey('splash'))
          : profile.hasCompletedOnboarding
          ? const _AppLockWrapper(
              key: ValueKey('home'),
              child: SavedCardsScreen(),
            )
          : const OnboardingScreen(key: ValueKey('onboarding')),
    );
  }
}

class _AppLockWrapper extends StatelessWidget {
  final Widget child;

  const _AppLockWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final appLockProvider = context.watch<AppLockProvider>();

    if (appLockProvider.isLocked && !appLockProvider.isAuthenticating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          appLockProvider.authenticate(context);
        }
      });
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // Keep the home screen mounted so async init/load isn't disposed mid-flight.
        TickerMode(
          enabled: !appLockProvider.isLocked,
          child: ExcludeSemantics(
            excluding: appLockProvider.isLocked,
            child: IgnorePointer(
              ignoring: appLockProvider.isLocked,
              child: child,
            ),
          ),
        ),
        if (appLockProvider.isLocked)
          ColoredBox(
            color: Theme.of(context).colorScheme.surface,
            child: const _AppLockOverlay(),
          ),
      ],
    );
  }
}

class _AppLockOverlay extends StatelessWidget {
  const _AppLockOverlay();

  @override
  Widget build(BuildContext context) {
    final appLockProvider = context.watch<AppLockProvider>();
    final scheme = Theme.of(context).colorScheme;

    return Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: 'CardVault locked',
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 112,
              height: 112,
              decoration: BoxDecoration(
                color: scheme.tertiaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.lock_outline_rounded,
                size: 54,
                color: scheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'CardVault is locked',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Authenticate to view your cards',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 32),
            if (!appLockProvider.isAuthenticating)
              FilledButton.icon(
                onPressed: () => appLockProvider.authenticate(context),
                icon: const Icon(Icons.fingerprint_rounded),
                label: const Text('Unlock'),
              ),
          ],
        ),
      ),
    );
  }
}
