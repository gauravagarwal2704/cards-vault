/// Shared spacing keeps screen rhythm consistent and makes adaptive changes
/// predictable.
class AppSpacing {
  AppSpacing._();

  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 20.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  static const xxxl = 40.0;

  static double pageHorizontal(double width) {
    if (width >= 1200) return 40;
    if (width >= 600) return 32;
    return 20;
  }
}
