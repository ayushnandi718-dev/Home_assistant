import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';

/// Translucent status badge with a softly lit indicator dot.
class GlassStatusBadge extends StatelessWidget {
  const GlassStatusBadge({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.showDot = true,
    this.dense = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool showDot;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final AuraPalette palette = AuraPaletteTheme.of(context);
    final Color resolvedColor = color ?? palette.textSecondary;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AuraSpace.xs : AuraSpace.sm,
        vertical: dense ? AuraSpace.xxs : AuraSpace.xs - 2,
      ),
      decoration: BoxDecoration(
        color: resolvedColor.withValues(alpha: dense ? 0.07 : 0.10),
        borderRadius: BorderRadius.circular(AuraRadius.pill),
        border: Border.all(color: resolvedColor.withValues(alpha: 0.26)),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: resolvedColor.withValues(alpha: 0.05), blurRadius: 12),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: AuraSpace.xs - 2),
              child: Icon(icon, size: dense ? 12 : 13, color: resolvedColor),
            )
          else if (showDot)
            Padding(
              padding: const EdgeInsets.only(right: AuraSpace.xs - 2),
              child: Container(
                width: dense ? 5 : 6,
                height: dense ? 5 : 6,
                decoration: BoxDecoration(
                  color: resolvedColor,
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                        color: resolvedColor.withValues(alpha: 0.55),
                        blurRadius: 7),
                  ],
                ),
              ),
            ),
          // Status labels can be long at large text scales. Let the label
          // wrap within the badge instead of overflowing the pill's Row.
          Flexible(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: dense ? 9.5 : 11,
                fontWeight: FontWeight.w600,
                color: resolvedColor,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact glass icon button used in bars and floating controls.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
    this.size = 40,
    this.selected = false,
    this.badge,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;
  final double size;
  final bool selected;
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final AuraPalette palette = AuraPaletteTheme.of(context);
    final Color resolved =
        color ?? (selected ? palette.primary : palette.textSecondary);
    final Widget button = GlassContainer(
      width: size,
      height: size,
      padding: EdgeInsets.zero,
      radius: AuraRadius.control,
      onTap: onPressed,
      accent: resolved,
      fill: selected ? 0.55 : 0.42,
      blur: 0,
      showHighlight: false,
      child: Center(
        child: badge != null
            ? Badge(label: badge, child: Icon(icon, size: 18, color: resolved))
            : Icon(icon, size: 18, color: resolved),
      ),
    );

    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
