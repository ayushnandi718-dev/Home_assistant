import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:aura_hub/theme/styles/bottom_navigation_bar_style.dart';
import 'package:forui/forui.dart';
import 'package:flutter/material.dart';

/// Builds the Forui theme used by AURA's mobile navigation.
///
/// AURA keeps its own Material theme and glass surfaces; Forui is used only
/// where its touch navigation primitives are a better fit. The generated style
/// functions are customised here so the active palette drives the result.
FThemeData auraForuiTheme(AuraPalette palette) {
  final FThemeData base = FTheme.neutral.dark.touch;
  final bool violet = palette.id == AuraPalette.violet.id;
  final FColors colors = base.colors.copyWith(
    primary: palette.primary,
    primaryForeground: Colors.white,
    secondary: palette.secondary,
    secondaryForeground: Colors.white,
    background: palette.backgroundDeep,
    foreground: palette.textPrimary,
    border: violet
        ? palette.border.withValues(alpha: palette.borderAlpha ?? 0.16)
        : base.colors.border,
  );

  return FThemeData(
    touch: true,
    debugLabel: 'AURA ${palette.id}',
    colors: colors,
    typography: base.typography,
    icons: base.icons,
    style: base.style,
    bottomNavigationBarStyle: bottomNavigationBarStyle(
      colors: colors,
      typography: base.typography,
      style: base.style,
      palette: palette,
    ),
  );
}
