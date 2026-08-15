import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/nfc_provider.dart';
import 'providers/camera_provider.dart';
import 'providers/card_view_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/app_lock_provider.dart';
import 'screens/saved_cards_screen.dart';

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
      ],
      child: Consumer2<ThemeProvider, AppLockProvider>(
        builder: (context, themeProvider, appLockProvider, child) {
          return MaterialApp(
            title: 'Cards Wallet',
            debugShowCheckedModeBanner: false,
            theme: themeProvider.currentTheme,
            home: _AppLockWrapper(
              child: const SavedCardsScreen(),
            ),
          );
        },
      ),
    );
  }
}

class _AppLockWrapper extends StatelessWidget {
  final Widget child;

  const _AppLockWrapper({required this.child});

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
          child: IgnorePointer(
            ignoring: appLockProvider.isLocked,
            child: child,
          ),
        ),
        if (appLockProvider.isLocked)
          const ColoredBox(
            color: Colors.black,
            child: _AppLockOverlay(),
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

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.lock_outline,
            size: 80,
            color: Colors.white,
          ),
          const SizedBox(height: 24),
          Text(
            'App Locked',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Authenticate to continue',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white70,
                ),
          ),
          const SizedBox(height: 32),
          if (!appLockProvider.isAuthenticating)
            TextButton(
              onPressed: () => appLockProvider.authenticate(context),
              child: const Text('Unlock'),
            ),
        ],
      ),
    );
  }
}
