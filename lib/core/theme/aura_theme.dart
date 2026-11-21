import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:flutter/material.dart';

const List<String> _fontFallback = <String>[
  'Segoe UI Variable Display',
  'Segoe UI',
  'Roboto',
  'sans-serif',
];

class _AuraPalette {
  const _AuraPalette({
    required this.brightness,
    required this.background,
    required this.surface,
    required this.elevated,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.onPrimary,
  });

  final Brightness brightness;
  final Color background;
  final Color surface;
  final Color elevated;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color onPrimary;

  static const _AuraPalette dark = _AuraPalette(
    brightness: Brightness.dark,
    background: AuraColors.background,
    surface: AuraColors.card,
    elevated: AuraColors.elevated,
    textPrimary: AuraColors.textPrimary,
    textSecondary: AuraColors.textSecondary,
    border: AuraColors.border,
    onPrimary: AuraColors.onAccent,
  );

  static const _AuraPalette light = _AuraPalette(
    brightness: Brightness.light,
    background: AuraColors.lightBackground,
    surface: AuraColors.lightSurface,
    elevated: AuraColors.lightElevated,
    textPrimary: AuraColors.lightTextPrimary,
    textSecondary: AuraColors.lightTextSecondary,
    border: AuraColors.lightBorder,
    onPrimary: AuraColors.onAccent,
  );
}

TextStyle _type(
  double size,
  FontWeight weight,
  Color color, {
  double height = 1.3,
  double spacing = 0,
}) {
  return TextStyle(
    fontFamily: 'Inter',
    fontFamilyFallback: _fontFallback,
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: spacing,
  );
}

/// Builds the AURA design language.
///
/// Dark remains the default and is byte-for-byte the original premium palette.
/// The light variant uses the same blue/violet accents with high-contrast
/// surfaces for users who explicitly select it.
ThemeData auraTheme({
  VisualDensity visualDensity = VisualDensity.standard,
  bool light = false,
  AuraPalette visual = AuraPalette.midnight,
}) {
  final _AuraPalette palette = light ? _AuraPalette.light : _AuraPalette.dark;
  final bool violet = visual.id == AuraPalette.violet.id;
  final Color background = violet ? visual.background : palette.background;
  final Color textPrimary = violet ? visual.textPrimary : palette.textPrimary;
  final Color textSecondary =
      violet ? visual.textSecondary : palette.textSecondary;
  final Color border = violet ? visual.lavender : palette.border;
  final Color elevated = violet ? visual.glassTint : palette.elevated;
  final ColorScheme scheme = ColorScheme(
    brightness: violet ? Brightness.dark : palette.brightness,
    primary: visual.primary,
    onPrimary: Colors.white,
    secondary: visual.secondary,
    onSecondary: Colors.white,
    error: AuraColors.danger,
    onError: background,
    surface: violet ? visual.glassTintLight : palette.surface,
    onSurface: textPrimary,
    surfaceContainerHighest: elevated,
    onSurfaceVariant: textSecondary,
    outline: border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: violet ? Brightness.dark : palette.brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    canvasColor: background,
    extensions: <ThemeExtension<dynamic>>[AuraPaletteTheme(visual)],
    fontFamily: 'Inter',
    visualDensity: visualDensity,
    splashFactory: InkRipple.splashFactory,
    // Route changes fade and drift forward instead of snapping between pages.
    // go_router builds MaterialPage instances, so this is what drives the
    // navigation transition (and avoids reparenting the shell navigator).
    pageTransitionsTheme: PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        for (final TargetPlatform platform in TargetPlatform.values)
          platform: const FadeForwardsPageTransitionsBuilder(),
      },
    ),
    textTheme: TextTheme(
      displayLarge: _type(
        44,
        FontWeight.w600,
        textPrimary,
        height: 1.1,
        spacing: -1.4,
      ),
      headlineLarge: _type(
        32,
        FontWeight.w600,
        textPrimary,
        height: 1.2,
        spacing: -0.8,
      ),
      headlineMedium: _type(
        24,
        FontWeight.w600,
        textPrimary,
        height: 1.25,
        spacing: -0.4,
      ),
      headlineSmall: _type(20, FontWeight.w600, textPrimary),
      titleLarge: _type(18, FontWeight.w600, textPrimary),
      titleMedium: _type(15, FontWeight.w600, textPrimary),
      titleSmall: _type(13, FontWeight.w600, textPrimary),
      bodyLarge: _type(15, FontWeight.w400, textPrimary, height: 1.5),
      bodyMedium: _type(13, FontWeight.w400, textSecondary, height: 1.5),
      bodySmall: _type(12, FontWeight.w400, textSecondary, height: 1.4),
      labelLarge: _type(13, FontWeight.w600, textPrimary, spacing: 0.2),
      labelMedium: _type(11, FontWeight.w600, textSecondary, spacing: 0.6),
      labelSmall: _type(10, FontWeight.w600, textSecondary, spacing: 0.8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: visual.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: elevated,
        disabledForegroundColor: textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: _type(13, FontWeight.w600, Colors.white),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: textPrimary,
        side: BorderSide(color: border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: _type(13, FontWeight.w600, textPrimary),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: visual.primary,
        textStyle: _type(13, FontWeight.w600, visual.primary),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll<Color>(textSecondary),
        overlayColor: WidgetStatePropertyAll<Color>(
          visual.primary.withValues(alpha: 0.10),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: elevated,
      surfaceTintColor: Colors.transparent,
      indicatorColor: visual.primary.withValues(alpha: 0.14),
      elevation: 0,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        _type(10, FontWeight.w600, textSecondary),
      ),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? visual.primary
              : textSecondary,
          size: 22,
        );
      }),
    ),
    dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: visual.primary,
      linearTrackColor: elevated,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: elevated,
      contentTextStyle: _type(13, FontWeight.w500, textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: _type(11, FontWeight.w500, textPrimary),
      decoration: BoxDecoration(
        color: elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStatePropertyAll<double>(6),
      thumbColor: WidgetStatePropertyAll<Color>(border),
      trackColor: WidgetStatePropertyAll<Color>(Colors.transparent),
    ),
  );
}
