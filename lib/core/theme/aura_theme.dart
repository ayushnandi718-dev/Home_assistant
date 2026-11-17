import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:flutter/material.dart';

const List<String> _fontFallback = <String>[
  'Segoe UI Variable Display',
  'Segoe UI',
  'Roboto',
  'sans-serif',
];

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

/// Builds the dark-first AURA design language.
ThemeData auraTheme() {
  const ColorScheme scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: AuraColors.primary,
    onPrimary: AuraColors.onAccent,
    secondary: AuraColors.secondary,
    onSecondary: AuraColors.onAccent,
    error: AuraColors.danger,
    onError: AuraColors.backgroundDeep,
    surface: AuraColors.card,
    onSurface: AuraColors.textPrimary,
    surfaceContainerHighest: AuraColors.elevated,
    onSurfaceVariant: AuraColors.textSecondary,
    outline: AuraColors.border,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    scaffoldBackgroundColor: AuraColors.background,
    canvasColor: AuraColors.background,
    fontFamily: 'Inter',
    visualDensity: VisualDensity.standard,
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
      displayLarge: _type(44, FontWeight.w600, AuraColors.textPrimary,
          height: 1.1, spacing: -1.4),
      headlineLarge: _type(32, FontWeight.w600, AuraColors.textPrimary,
          height: 1.2, spacing: -0.8),
      headlineMedium: _type(24, FontWeight.w600, AuraColors.textPrimary,
          height: 1.25, spacing: -0.4),
      headlineSmall: _type(20, FontWeight.w600, AuraColors.textPrimary),
      titleLarge: _type(18, FontWeight.w600, AuraColors.textPrimary),
      titleMedium: _type(15, FontWeight.w600, AuraColors.textPrimary),
      titleSmall: _type(13, FontWeight.w600, AuraColors.textPrimary),
      bodyLarge:
          _type(15, FontWeight.w400, AuraColors.textPrimary, height: 1.5),
      bodyMedium:
          _type(13, FontWeight.w400, AuraColors.textSecondary, height: 1.5),
      bodySmall:
          _type(12, FontWeight.w400, AuraColors.textSecondary, height: 1.4),
      labelLarge:
          _type(13, FontWeight.w600, AuraColors.textPrimary, spacing: 0.2),
      labelMedium:
          _type(11, FontWeight.w600, AuraColors.textSecondary, spacing: 0.6),
      labelSmall:
          _type(10, FontWeight.w600, AuraColors.textSecondary, spacing: 0.8),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AuraColors.primary,
        foregroundColor: AuraColors.onAccent,
        disabledBackgroundColor: AuraColors.elevated,
        disabledForegroundColor: AuraColors.textSecondary,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: _type(13, FontWeight.w600, AuraColors.onAccent),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AuraColors.textPrimary,
        side: const BorderSide(color: AuraColors.border),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        textStyle: _type(13, FontWeight.w600, AuraColors.textPrimary),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AuraColors.primary,
        textStyle: _type(13, FontWeight.w600, AuraColors.primary),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        foregroundColor:
            WidgetStatePropertyAll<Color>(AuraColors.textSecondary),
        overlayColor: WidgetStatePropertyAll<Color>(
          AuraColors.primary.withValues(alpha: 0.10),
        ),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AuraColors.sidebar,
      surfaceTintColor: Colors.transparent,
      indicatorColor: AuraColors.primary.withValues(alpha: 0.14),
      elevation: 0,
      height: 72,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStatePropertyAll<TextStyle>(
        _type(10, FontWeight.w600, AuraColors.textSecondary),
      ),
      iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
        return IconThemeData(
          color: states.contains(WidgetState.selected)
              ? AuraColors.primary
              : AuraColors.textSecondary,
          size: 22,
        );
      }),
    ),
    dividerTheme: const DividerThemeData(
      color: AuraColors.border,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AuraColors.primary,
      linearTrackColor: AuraColors.elevated,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: AuraColors.elevated,
      contentTextStyle: _type(13, FontWeight.w500, AuraColors.textPrimary),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AuraColors.border),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 350),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      textStyle: _type(11, FontWeight.w500, AuraColors.textPrimary),
      decoration: BoxDecoration(
        color: AuraColors.elevated,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AuraColors.border),
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStatePropertyAll<double>(6),
      thumbColor: WidgetStatePropertyAll<Color>(AuraColors.border),
      trackColor: WidgetStatePropertyAll<Color>(Colors.transparent),
    ),
  );
}
