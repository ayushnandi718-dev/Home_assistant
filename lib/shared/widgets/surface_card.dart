import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';

/// The standard AURA bento surface.
///
/// Backed by [GlassContainer], so every screen gets the same translucency,
/// border, shadow and hover behaviour from one place. Telemetry cards use the
/// more opaque [AuraGlassSurface.card] preset by default to keep numbers crisp.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AuraSpace.lg),
    this.color,
    this.gradient,
    this.onTap,
    this.borderColor,
    this.radius = AuraRadius.card,
    this.surface = AuraGlassSurface.card,
    this.accent = AuraColors.primary,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double radius;
  final AuraGlassSurface surface;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Gradient? resolvedGradient = gradient ??
        (color == null
            ? null
            : LinearGradient(colors: <Color>[color!, color!]));

    return GlassContainer(
      surface: surface,
      padding: padding,
      gradient: resolvedGradient,
      onTap: onTap,
      borderColor: borderColor,
      radius: radius,
      accent: accent,
      child: child,
    );
  }
}
