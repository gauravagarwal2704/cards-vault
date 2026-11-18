import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'providers/nfc_provider.dart';
import 'providers/camera_provider.dart';
import 'providers/card_view_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/app_lock_provider.dart';
import 'providers/app_icon_provider.dart';
import 'providers/profile_provider.dart';
import 'services/auth_service.dart';
import 'services/home_widget_service.dart';
import 'models/app_icon_option.dart';
import 'screens/onboarding_screen.dart';
import 'screens/saved_cards_screen.dart';
import 'services/security_service.dart';
import 'services/app_log_service.dart';
import 'services/support_purchase_service.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';
import 'widgets/app_icon_artwork.dart';
import 'utils/debug_logger.dart';

bool _nativeSplashDeferred = false;

void main() {
  runZonedGuarded<void>(
    () {
      final binding = WidgetsFlutterBinding.ensureInitialized();
      AppLogService.instance.startCapture();
      unawaited(DebugLogger.initialize());
      // Subscribe before the first screen so delayed Google Play purchases are
      // acknowledged even if Settings is not open. Product and price queries
      // remain lazy until the supporter page is opened.
      unawaited(SupportPurchaseService.instance.startListening());
      binding.deferFirstFrame();
      _nativeSplashDeferred = true;
      runApp(const MyApp());
    },
    (error, stackTrace) {
      AppLogService.instance.recordFailure(
        'Unhandled Dart zone error',
        error,
        stackTrace,
        category: 'DartZone',
        fatal: true,
      );
    },
  );
}

class MyApp extends StatefulWidget {
  const MyApp({
    super.key,
    this.appLockProviderFactory,
    this.securityInitializer,
  });

  final AppLockProvider Function()? appLockProviderFactory;
  final Future<void> Function()? securityInitializer;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  bool _vaultReady = false;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AuthenticationCoordinator>.value(
          value: SecurityService().authentication,
        ),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AppIconProvider()),
        ChangeNotifierProvider(
          create: (_) =>
              widget.appLockProviderFactory?.call() ?? AppLockProvider(),
        ),
        ChangeNotifierProvider(create: (_) => NfcProvider()),
        ChangeNotifierProvider(create: (_) => CameraProvider()),
        ChangeNotifierProvider(create: (_) => CardViewProvider()),
        ChangeNotifierProvider(create: (_) => ProfileProvider()),
      ],
      child: Consumer2<ThemeProvider, AppLockProvider>(
        builder: (context, themeProvider, appLockProvider, child) {
          HomeWidgetService.instance.updateTheme(
            themeProvider.getPrimaryColor(),
            themeProvider.getPrimaryContainerColor(),
            refreshWidgets:
                _vaultReady &&
                appLockProvider.isInitialized &&
                !appLockProvider.isLocked,
          );
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
                child: _AppLockWrapper(
                  active:
                      _vaultReady &&
                      context.watch<ProfileProvider>().hasCompletedOnboarding,
                  child: child ?? const SizedBox.shrink(),
                ),
              );
            },
            home: _AppEntry(
              securityInitializer: widget.securityInitializer,
              onReady: () {
                if (mounted) setState(() => _vaultReady = true);
              },
            ),
          );
        },
      ),
    );
  }
}

class _AppEntry extends StatefulWidget {
  const _AppEntry({this.securityInitializer, required this.onReady});

  final VoidCallback onReady;

  final Future<void> Function()? securityInitializer;

  @override
  State<_AppEntry> createState() => _AppEntryState();
}

class _AppEntryState extends State<_AppEntry> {
  bool _showSelectedIconSplash = true;
  bool _splashExitScheduled = false;
  bool _securityInitialized = false;
  bool _hasUnlocked = false;

  @override
  void initState() {
    super.initState();
    _initializeSecurity();
    unawaited(HomeWidgetService.instance.start());
  }

  Future<void> _initializeSecurity() async {
    final span = AppLogService.instance.startSpan(
      'Startup',
      'Initialize security',
    );
    try {
      await (widget.securityInitializer ?? SecurityService().initialize)();
      span.complete();
      if (mounted) setState(() => _securityInitialized = true);
    } catch (error, stackTrace) {
      span.fail(error, stackTrace);
      // Remain on the non-sensitive initialization surface if native security
      // controls cannot be established.
      debugPrint('Security initialization failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<ProfileProvider>();
    final theme = context.watch<ThemeProvider>();
    final appIcon = context.watch<AppIconProvider>();
    final appLock = context.watch<AppLockProvider>();
    final ready =
        _securityInitialized &&
        appLock.isInitialized &&
        profile.isInitialized &&
        theme.isInitialized &&
        appIcon.isInitialized;
    if (ready && !_splashExitScheduled) {
      _splashExitScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_nativeSplashDeferred) {
          _nativeSplashDeferred = false;
          WidgetsBinding.instance.allowFirstFrame();
        }
        Future<void>.delayed(const Duration(milliseconds: 420), () {
          if (mounted) {
            setState(() => _showSelectedIconSplash = false);
            widget.onReady();
          }
        });
      });
    }

    if (ready && !appLock.isLocked) _hasUnlocked = true;
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
          ? ColoredBox(
              key: const ValueKey('initializing'),
              color: Theme.of(context).colorScheme.surface,
            )
          : _showSelectedIconSplash
          ? _SelectedAppIconSplash(
              key: const ValueKey('selected-icon-splash'),
              option: appIcon.selected,
            )
          : profile.hasCompletedOnboarding
          ? _hasUnlocked
                ? const SavedCardsScreen(key: ValueKey('home'))
                : const SizedBox.shrink(key: ValueKey('awaiting-unlock'))
          : const OnboardingScreen(key: ValueKey('onboarding')),
    );
  }
}

class _SelectedAppIconSplash extends StatelessWidget {
  const _SelectedAppIconSplash({super.key, required this.option});

  final AppIconOption option;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surface,
      child: Center(
        child: AppIconArtwork(
          option: option,
          size: 168,
          borderRadius: 42,
          addSurfaceShadow: true,
        ),
      ),
    );
  }
}

class _AppLockWrapper extends StatefulWidget {
  final Widget child;
  final bool active;

  const _AppLockWrapper({required this.child, required this.active});

  @override
  State<_AppLockWrapper> createState() => _AppLockWrapperState();
}

class _AppLockWrapperState extends State<_AppLockWrapper> {
  bool _attemptedUnlock = false;

  @override
  Widget build(BuildContext context) {
    final appLockProvider = context.watch<AppLockProvider>();

    final locked = widget.active && appLockProvider.isLocked;
    if (!locked) _attemptedUnlock = false;
    if (locked && !_attemptedUnlock && !appLockProvider.isAuthenticating) {
      _attemptedUnlock = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          appLockProvider.authenticate(context);
        }
      });
    }

    // Keep the Navigator mounted while hiding every route, including deep links.
    // Removing it on lock would discard the pending destination and back stack.
    return Stack(
      fit: StackFit.expand,
      children: [
        Offstage(
          offstage: locked,
          child: TickerMode(enabled: !locked, child: widget.child),
        ),
        if (locked)
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
