import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:flutter/material.dart';

/// A complete, swappable AURA visual palette.
///
/// `midnight` is byte-for-byte the existing navy/blue identity. `violet` is the
/// premium Android theme: saturated purple backdrop, white lavender glass and
/// high-contrast text. Both palettes carry only presentation values; no feature
/// state, security policy or device behaviour is derived from them.
@immutable
class AuraPalette {
  const AuraPalette({
    required this.id,
    required this.background,
    required this.backgroundDeep,
    required this.backgroundEdge,
    required this.primary,
    required this.secondary,
    required this.lavender,
    required this.highlight,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.glassTint,
    required this.glassTintLight,
    required this.ambientTopRight,
    required this.ambientBottomLeft,
    required this.ambientMidLeft,
    this.cardFill,
    this.strongFill,
    this.panelFill,
    this.chromeFill,
    this.floatingFill,
    this.borderAlpha,
  });

  final String id;
  final Color background;
  final Color backgroundDeep;
  final Color backgroundEdge;
  final Color primary;
  final Color secondary;
  final Color lavender;
  final Color highlight;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color glassTint;
  final Color glassTintLight;
  final List<Color> ambientTopRight;
  final List<Color> ambientBottomLeft;
  final List<Color> ambientMidLeft;

  /// Null means "use the original AuraGlass recipe" on Windows.
  final double? cardFill;
  final double? strongFill;
  final double? panelFill;
  final double? chromeFill;
  final double? floatingFill;
  final double? borderAlpha;

  static const AuraPalette midnight = AuraPalette(
    id: 'midnight',
    background: AuraColors.background,
    backgroundDeep: AuraColors.backgroundDeep,
    backgroundEdge: Color(0xFF060910),
    primary: AuraColors.primary,
    secondary: AuraColors.secondary,
    lavender: AuraColors.secondary,
    highlight: AuraColors.warning,
    textPrimary: AuraColors.textPrimary,
    textSecondary: AuraColors.textSecondary,
    border: AuraColors.border,
    glassTint: AuraGlass.tint,
    glassTintLight: AuraGlass.tintLight,
    ambientTopRight: AuraGlass.ambientBlue,
    ambientBottomLeft: AuraGlass.ambientViolet,
    ambientMidLeft: AuraGlass.ambientCyan,
  );

  static const AuraPalette violet = AuraPalette(
    id: 'violet',
    // Deep violet background with brighter violet reserved for interactive
    // accents. Ambient orbs and glass fills are deliberately restrained so
    // secondary text stays readable and cards do not all glow equally.
    background: Color(0xFF3A0F78),
    backgroundDeep: Color(0xFF240A55),
    backgroundEdge: Color(0xFF140632),
    primary: Color(0xFF8B45FF),
    secondary: Color(0xFFC6A6FF),
    lavender: Color(0xFFD8C7FF),
    highlight: Color(0xFFFFD95A),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFF0E9FF),
    border: Color(0xFFD8C7FF),
    glassTint: Color(0xFF190A3B),
    glassTintLight: Color(0xFF2C125F),
    ambientTopRight: <Color>[
      Color(0x2ED9C2FF),
      Color(0x10B58AFF),
      Color(0x00000000),
    ],
    ambientBottomLeft: <Color>[
      Color(0x3A8B45FF),
      Color(0x14240A55),
      Color(0x00000000),
    ],
    ambientMidLeft: <Color>[
      Color(0x24D9C2FF),
      Color(0x088B45FF),
      Color(0x00000000),
    ],
    cardFill: 0.64,
    strongFill: 0.74,
    panelFill: 0.46,
    chromeFill: 0.34,
    floatingFill: 0.30,
    borderAlpha: 0.16,
  );

  double fillFor(AuraGlassSurface surface, double fallback) =>
      switch (surface) {
        AuraGlassSurface.card => cardFill ?? fallback,
        AuraGlassSurface.strong => strongFill ?? fallback,
        AuraGlassSurface.panel => panelFill ?? fallback,
        AuraGlassSurface.chrome => chromeFill ?? fallback,
        AuraGlassSurface.floating => floatingFill ?? fallback,
      };
}

/// Makes the active palette available to any descendant without passing it
/// through every constructor.
final class AuraPaletteTheme extends ThemeExtension<AuraPaletteTheme> {
  const AuraPaletteTheme(this.palette);

  final AuraPalette palette;

  static AuraPalette of(BuildContext context) =>
      Theme.of(context).extension<AuraPaletteTheme>()?.palette ??
      AuraPalette.midnight;

  @override
  AuraPaletteTheme copyWith({AuraPalette? palette}) =>
      AuraPaletteTheme(palette ?? this.palette);

  @override
  AuraPaletteTheme lerp(ThemeExtension<AuraPaletteTheme>? other, double t) =>
      this;
}
