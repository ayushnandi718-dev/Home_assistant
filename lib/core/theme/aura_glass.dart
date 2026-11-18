import 'package:flutter/material.dart';

/// How strongly a surface reads as "glass".
///
/// Chrome and floating surfaces carry the most blur and the most transparent
/// fill; data cards are deliberately more opaque so numbers stay legible.
enum AuraGlassSurface {
  /// Sidebar, top bar and other persistent navigation chrome.
  chrome,

  /// Large content panels and grouped sections.
  panel,

  /// Telemetry and bento cards. Highest fill, lowest blur.
  card,

  /// A card that must win against a busy backdrop (selected/active state).
  strong,

  /// Dialogs, menus and popovers.
  floating,
}

/// Single source of truth for AURA's layered glass language.
///
/// Values are intentionally restrained: enough blur and translucency to feel
/// premium, but never so much that text or live telemetry becomes hard to read.
abstract final class AuraGlass {
  // ---- Accent lighting ----------------------------------------------------
  static const Color cyan = Color(0xFF62D9F2);
  static const Color glowBlue = Color(0xFF3D7DFF);
  static const Color glowViolet = Color(0xFF8B6CFF);

  /// Neutral tint laid over the backdrop to create the glass body.
  static const Color tint = Color(0xFF10192A);
  static const Color tintLight = Color(0xFF16233A);

  /// Thin top-edge highlight that sells the glass thickness.
  static const Color highlight = Color(0xFFFFFFFF);

  // ---- Blur ---------------------------------------------------------------
  static const double blurCard = 6;
  static const double blurPanel = 12;
  static const double blurChrome = 18;
  static const double blurFloating = 22;

  // ---- Fill opacity -------------------------------------------------------
  static const double fillFloating = 0.12;
  static const double fillChrome = 0.20;
  static const double fillPanel = 0.34;
  static const double fillCard = 0.72;
  static const double fillCardStrong = 0.84;

  // ---- Border opacity -----------------------------------------------------
  static const double borderSoft = 0.12;
  static const double border = 0.22;
  static const double borderStrong = 0.38;

  // ---- Elevation ----------------------------------------------------------
  static const List<BoxShadow> elevationLow = <BoxShadow>[
    BoxShadow(color: Color(0x2A050910), blurRadius: 12, offset: Offset(0, 4)),
  ];
  static const List<BoxShadow> elevationMedium = <BoxShadow>[
    BoxShadow(color: Color(0x3D050910), blurRadius: 28, offset: Offset(0, 12)),
  ];
  static const List<BoxShadow> elevationHigh = <BoxShadow>[
    BoxShadow(color: Color(0x52050A14), blurRadius: 48, offset: Offset(0, 20)),
    BoxShadow(color: Color(0x141B2B5C), blurRadius: 18, offset: Offset(0, 4)),
  ];

  /// Accent glow applied only on hover / active states.
  static BoxShadow glow(Color accent) => BoxShadow(
        color: accent.withValues(alpha: 0.14),
        blurRadius: 30,
        spreadRadius: -6,
        offset: const Offset(0, 8),
      );

  /// Resolved visual recipe for a surface kind.
  static const AuraGlassSpec specChrome = AuraGlassSpec(
    blur: blurChrome,
    fill: fillChrome,
    borderAlpha: border,
    shadows: elevationMedium,
  );
  static const AuraGlassSpec specPanel = AuraGlassSpec(
    blur: blurPanel,
    fill: fillPanel,
    borderAlpha: borderSoft,
    shadows: elevationLow,
  );
  static const AuraGlassSpec specCard = AuraGlassSpec(
    blur: blurCard,
    fill: fillCard,
    borderAlpha: borderSoft,
    shadows: elevationMedium,
  );
  static const AuraGlassSpec specStrong = AuraGlassSpec(
    blur: blurCard,
    fill: fillCardStrong,
    borderAlpha: borderStrong,
    shadows: elevationHigh,
  );
  static const AuraGlassSpec specFloating = AuraGlassSpec(
    blur: blurFloating,
    fill: fillFloating,
    borderAlpha: border,
    shadows: elevationHigh,
  );

  static AuraGlassSpec spec(AuraGlassSurface surface) {
    switch (surface) {
      case AuraGlassSurface.chrome:
        return specChrome;
      case AuraGlassSurface.panel:
        return specPanel;
      case AuraGlassSurface.card:
        return specCard;
      case AuraGlassSurface.strong:
        return specStrong;
      case AuraGlassSurface.floating:
        return specFloating;
    }
  }

  /// A restrained top-to-bottom sheen used on glass bodies.
  static LinearGradient sheen(Color tint, double fill) => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          tintLight.withValues(alpha: fill * 0.92),
          tint.withValues(alpha: fill),
        ],
      );

  /// Radial lighting used behind the shell. Kept as one widget tree so it
  /// repaints once rather than per card.
  static const List<Color> ambientBlue = <Color>[
    Color(0x2E3D7DFF),
    Color(0x0D3D7DFF),
    Color(0x00000000),
  ];
  static const List<Color> ambientViolet = <Color>[
    Color(0x268B6CFF),
    Color(0x0A8B6CFF),
    Color(0x00000000),
  ];
  static const List<Color> ambientCyan = <Color>[
    Color(0x1E62D9F2),
    Color(0x0062D9F2),
    Color(0x00000000),
  ];
}

/// Immutable visual recipe for one glass surface.
class AuraGlassSpec {
  const AuraGlassSpec({
    required this.blur,
    required this.fill,
    required this.borderAlpha,
    required this.shadows,
  });

  final double blur;
  final double fill;
  final double borderAlpha;
  final List<BoxShadow> shadows;
}
