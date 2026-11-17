import 'package:flutter/material.dart';

/// Motion tokens shared by every AURA Hub transition.
///
/// Keeping durations and curves in one place makes the whole app feel like it
/// moves at the same speed, instead of every widget picking its own timing.
abstract final class AuraMotion {
  /// Quick feedback (taps, icon swaps, hover changes).
  static const Duration fast = Duration(milliseconds: 160);

  /// Default transition for content entering or leaving the screen.
  static const Duration medium = Duration(milliseconds: 260);

  /// Larger layout moves, such as the sidebar changing width.
  static const Duration slow = Duration(milliseconds: 340);

  /// Balanced ease used for continuous layout changes (e.g. width).
  static const Cubic standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Deceleration for elements arriving on screen.
  static const Cubic enter = Cubic(0.0, 0.0, 0.2, 1.0);

  /// Acceleration for elements leaving the screen.
  static const Cubic exit = Cubic(0.4, 0.0, 1.0, 1.0);

  /// Honours the OS "reduce animations" accessibility setting.
  static Duration of(BuildContext context, Duration duration) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : duration;
}
