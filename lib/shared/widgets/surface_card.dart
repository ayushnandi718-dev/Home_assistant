import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

/// Reusable bento surface with a fine border, soft shadow and subtle hover.
class SurfaceCard extends StatefulWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AuraSpace.lg),
    this.color,
    this.gradient,
    this.onTap,
    this.borderColor,
    this.radius = AuraRadius.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Gradient? gradient;
  final VoidCallback? onTap;
  final Color? borderColor;
  final double radius;

  @override
  State<SurfaceCard> createState() => _SurfaceCardState();
}

class _SurfaceCardState extends State<SurfaceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(widget.radius);
    final bool interactive = widget.onTap != null;
    final Color border = widget.borderColor ??
        (interactive && _hovered
            ? AuraColors.primary.withValues(alpha: 0.38)
            : AuraColors.border.withValues(alpha: 0.85));

    return MouseRegion(
      onEnter: interactive ? (_) => setState(() => _hovered = true) : null,
      onExit: interactive ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: AuraMotion.of(context, AuraMotion.medium),
        curve: AuraMotion.enter,
        decoration: BoxDecoration(
          color: widget.gradient == null
              ? (widget.color ?? AuraColors.card)
              : null,
          gradient: widget.gradient,
          borderRadius: radius,
          border: Border.all(color: border),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: AuraColors.backgroundDeep.withValues(alpha: 0.42),
              blurRadius: 28,
              offset: const Offset(0, 12),
            ),
            if (interactive && _hovered)
              BoxShadow(
                color: AuraColors.primary.withValues(alpha: 0.08),
                blurRadius: 36,
                offset: const Offset(0, 10),
              ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          child: InkWell(
            onTap: widget.onTap,
            hoverColor:
                interactive ? AuraColors.primary.withValues(alpha: 0.03) : null,
            borderRadius: radius,
            child: Padding(
              padding: widget.padding,
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}
