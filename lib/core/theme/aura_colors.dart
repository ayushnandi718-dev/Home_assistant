import 'package:flutter/material.dart';

/// Single source of truth for every colour used by AURA Hub.
abstract final class AuraColors {
  static const Color background = Color(0xFF0B0F17);
  static const Color backgroundDeep = Color(0xFF080B11);
  static const Color sidebar = Color(0xFF101722);
  static const Color card = Color(0xFF121925);
  static const Color elevated = Color(0xFF182334);

  static const Color primary = Color(0xFF78AFFF);
  static const Color secondary = Color(0xFF9B8CFF);

  static const Color textPrimary = Color(0xFFF3F6FC);
  static const Color textSecondary = Color(0xFF8998AC);
  static const Color border = Color(0xFF263243);

  static const Color success = Color(0xFF63E6BE);
  static const Color warning = Color(0xFFF5C97B);
  static const Color danger = Color(0xFFFF7A8A);

  static const Color onAccent = Color(0xFF07111F);

  /// Light-theme surfaces. Kept separate so the dark AURA palette used by the
  /// glass system is never mutated or degraded.
  static const Color lightBackground = Color(0xFFF4F7FC);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightElevated = Color(0xFFE8EFF8);
  static const Color lightTextPrimary = Color(0xFF101722);
  static const Color lightTextSecondary = Color(0xFF526174);
  static const Color lightBorder = Color(0xFFD3DEEC);
}
