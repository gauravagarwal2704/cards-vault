import 'package:flutter/material.dart';

/// Shared motion values keep interactions feeling like one coherent system.
class AppMotion {
  AppMotion._();

  /// Non-spatial effects such as color, opacity, and selection marks.
  static const quick = Duration(milliseconds: 160);

  /// Local spatial changes such as expanding controls and rearranging items.
  static const standard = Duration(milliseconds: 280);

  /// Hero moments such as card-to-detail and successful capture transitions.
  static const emphasized = Duration(milliseconds: 440);

  static const enterCurve = Curves.easeOutBack;
  static const standardCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;

  static bool reduceMotion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  static Duration resolve(BuildContext context, Duration duration) =>
      reduceMotion(context) ? Duration.zero : duration;

  /// A quick, lightly elastic settle for direct-manipulation surfaces.
  static const carouselSpring = SpringDescription(
    mass: 1,
    stiffness: 390,
    damping: 34,
  );

  /// Slightly firmer than the carousel so swipe actions do not feel loose.
  static const actionSpring = SpringDescription(
    mass: 1,
    stiffness: 460,
    damping: 38,
  );
}

/// A restrained fade/scale transition used by routes throughout the app.
class CardVaultPageTransitionsBuilder extends PageTransitionsBuilder {
  const CardVaultPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (route.isFirst || AppMotion.reduceMotion(context)) return child;

    final curved = CurvedAnimation(
      parent: animation,
      curve: AppMotion.standardCurve,
      reverseCurve: AppMotion.exitCurve,
    );

    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.025),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      ),
    );
  }
}

/// Adds tactile scale feedback without taking ownership of the tap gesture.
class PressableScale extends StatefulWidget {
  final Widget child;
  final double pressedScale;
  final BorderRadius? borderRadius;

  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.975,
    this.borderRadius,
  });

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _isPressed = false;

  void _setPressed(bool value) {
    if (!mounted || _isPressed == value) return;
    setState(() => _isPressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final duration = AppMotion.resolve(context, AppMotion.quick);
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _isPressed ? widget.pressedScale : 1,
        duration: duration,
        curve: AppMotion.standardCurve,
        child: widget.child,
      ),
    );
  }
}
