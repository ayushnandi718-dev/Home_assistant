import 'package:flutter/widgets.dart';

abstract final class AuraSpace {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
}

abstract final class AuraRadius {
  static const double control = 12;
  static const double card = 20;
  static const double panel = 24;

  /// Mobile bottom-navigation capsule. Shared by the Forui style and the
  /// rounded-rect blur clip so the glass never extends past the capsule.
  static const double navCapsule = 28;

  static const double pill = 999;
}

abstract final class AuraBreakpoints {
  static const double mobile = 700;
  static const double desktop = 1100;
  static const double content = 1440;
}

/// Height of the soft scrim behind the floating mobile navigation. Scrollable
/// pages reserve at least this much bottom padding so the final card clears the
/// capsule instead of hiding beneath it.
const double mobileNavFadeHeight = 120;

double pageHorizontalPadding(double width) {
  if (width >= 1400) return AuraSpace.xl;
  if (width >= 760) return AuraSpace.lg;
  return AuraSpace.md;
}

/// Logical pixels currently taken by the on-screen keyboard or another
/// bottom system view. AURA uses `adjustResize` on Android, so the shell
/// body shrinks by this amount while the composer must stay visible.
double auraKeyboardInset(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom;

/// True while the keyboard is open or the viewport is unusually short.
///
/// `Scaffold(resizeToAvoidBottomInset: true)` removes view insets from its
/// descendants, so pages inside the shell must also pass the height reported
/// by their own `LayoutBuilder`. That height shrinks under Android's
/// `adjustResize`, which is the reliable signal on a real device.
bool auraDenseLayout(
  BuildContext context, {
  double? availableHeight,
}) {
  if (auraKeyboardInset(context) > 0) return true;
  final double height = availableHeight ?? MediaQuery.sizeOf(context).height;
  // Large accessibility text makes fixed chrome taller, so the threshold
  // grows with the user's text scale.
  final double scale = MediaQuery.textScalerOf(context).scale(14) / 14;
  return height < 560 * (scale > 0 ? scale : 1);
}
