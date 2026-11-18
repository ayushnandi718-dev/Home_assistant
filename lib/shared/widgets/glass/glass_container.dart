import 'dart:ui' as ui;

import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

/// The primitive behind every AURA glass surface.
///
/// A single translucent body sits over a blurred copy of whatever is behind it
/// (the shell's ambient lighting), with a fine border, controlled shadow and a
/// restrained top-edge highlight. Blur and fill come from [AuraGlass] presets so
/// chrome/dialogs read as glass while data cards stay legible.
class GlassContainer extends StatefulWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.surface = AuraGlassSurface.card,
    this.padding = const EdgeInsets.all(AuraSpace.lg),
    this.margin,
    this.width,
    this.height,
    this.radius = AuraRadius.card,
    this.blur,
    this.fill,
    this.borderColor,
    this.borderAlpha,
    this.border,
    this.shadows,
    this.gradient,
    this.accent = AuraColors.primary,
    this.alignment,
    this.showHighlight = true,
    this.onTap,
  });

  final Widget child;
  final AuraGlassSurface surface;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;
  final double radius;
  final double? blur;
  final double? fill;
  final Color? borderColor;
  final double? borderAlpha;
  final BoxBorder? border;
  final List<BoxShadow>? shadows;
  final Gradient? gradient;
  final Color accent;
  final AlignmentGeometry? alignment;
  final bool showHighlight;
  final VoidCallback? onTap;

  @override
  State<GlassContainer> createState() => _GlassContainerState();
}

class _GlassContainerState extends State<GlassContainer> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final AuraGlassSpec spec = AuraGlass.spec(widget.surface);
    final bool interactive = widget.onTap != null;
    // Static surfaces never animate their border or shadow. Skipping the
    // implicit animation controllers keeps telemetry polls and scrolling from
    // creating idle tickers for every card on the page.
    final Duration duration =
        interactive ? AuraMotion.of(context, AuraMotion.medium) : Duration.zero;
    final bool hovered = interactive && _hovered;
    final bool pressed = interactive && _pressed;
    final double blur = widget.blur ?? spec.blur;

    final Color border = widget.borderColor ??
        AuraGlass.highlight.withValues(
          alpha: pressed
              ? AuraGlass.borderStrong
              : hovered
                  ? 0.28
                  : widget.borderAlpha ?? spec.borderAlpha,
        );

    final List<BoxShadow> baseShadows = widget.shadows ?? spec.shadows;
    final List<BoxShadow> resolvedShadows = hovered && !pressed
        ? <BoxShadow>[...baseShadows, AuraGlass.glow(widget.accent)]
        : baseShadows;

    final BorderRadius borderRadius = BorderRadius.circular(widget.radius);

    // Keep a transparent Material directly around the child so descendants
    // such as ListTile paint their ink above the translucent glass body.
    final Widget materializedChild = Material(
      type: MaterialType.transparency,
      borderRadius: borderRadius,
      child: widget.child,
    );

    final BoxDecoration bodyDecoration = BoxDecoration(
      color: widget.gradient == null
          ? AuraGlass.tint.withValues(alpha: widget.fill ?? spec.fill)
          : null,
      gradient: widget.gradient ??
          AuraGlass.sheen(AuraGlass.tint, widget.fill ?? spec.fill),
      borderRadius: borderRadius,
      border: widget.border ?? Border.all(color: border),
    );

    Widget body = interactive
        ? AnimatedContainer(
            duration: duration,
            curve: AuraMotion.enter,
            alignment: widget.alignment,
            padding: widget.padding,
            decoration: bodyDecoration,
            child: materializedChild,
          )
        : Container(
            alignment: widget.alignment,
            padding: widget.padding,
            decoration: bodyDecoration,
            child: materializedChild,
          );

    // BackdropFilter only reads pixels that are actually behind the panel. It
    // is wrapped by ClipRRect so the blur never bleeds past the rounded edge.
    if (blur > 0) {
      body = ClipRRect(
        borderRadius: borderRadius,
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: body,
        ),
      );
    }

    // Shadow lives on an outer layer because ClipRRect would cut it off.
    final BoxDecoration shadowDecoration = BoxDecoration(
      borderRadius: borderRadius,
      boxShadow: resolvedShadows,
    );
    Widget result = interactive
        ? AnimatedContainer(
            duration: duration,
            curve: AuraMotion.enter,
            margin: widget.margin,
            width: widget.width,
            height: widget.height,
            decoration: shadowDecoration,
            child: body,
          )
        : Container(
            margin: widget.margin,
            width: widget.width,
            height: widget.height,
            decoration: shadowDecoration,
            child: body,
          );

    if (widget.showHighlight) {
      result = Stack(
        children: <Widget>[
          result,
          Positioned(
            top: 0,
            left: widget.radius,
            right: widget.radius,
            child: IgnorePointer(
              child: Container(
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Color(0x00000000),
                      AuraGlass.highlight
                          .withValues(alpha: hovered ? 0.26 : 0.14),
                      Color(0x00000000),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (interactive) {
      // A very small press scale gives tactile feedback; AuraMotion collapses
      // the duration to zero when the OS requests reduced animations.
      result = AnimatedScale(
        scale: pressed ? AuraGlass.pressedScale : 1,
        duration: AuraMotion.of(context, AuraMotion.fast),
        curve: AuraMotion.standard,
        child: result,
      );
      result = MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: borderRadius,
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            borderRadius: borderRadius,
            splashColor: widget.accent.withValues(alpha: 0.10),
            highlightColor: widget.accent.withValues(alpha: 0.04),
            child: result,
          ),
        ),
      );
    }

    return result;
  }
}

/// Convenience wrapper for the common translucent data-card case.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AuraSpace.lg),
    this.onTap,
    this.accent = AuraColors.primary,
    this.radius = AuraRadius.card,
    this.borderColor,
    this.surface = AuraGlassSurface.card,
    this.width,
    this.height,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color accent;
  final double radius;
  final Color? borderColor;
  final AuraGlassSurface surface;
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return GlassContainer(
      surface: surface,
      padding: padding,
      onTap: onTap,
      accent: accent,
      radius: radius,
      borderColor: borderColor,
      width: width,
      height: height,
      child: child,
    );
  }
}
