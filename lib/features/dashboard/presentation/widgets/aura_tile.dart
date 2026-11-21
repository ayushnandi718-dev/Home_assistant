import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

/// How a tile should present its data.
enum AuraTileState { normal, loading, unavailable }

/// The single reusable SmartThings-style surface used by the mobile Dashboard.
///
/// Accent colour is the only per-tile styling decision: radius, padding,
/// gradient strength and interaction all come from here so the grid stays
/// visually consistent. [height] is a minimum, which keeps large accessibility
/// text from clipping.
class AuraTile extends StatelessWidget {
  const AuraTile({
    super.key,
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
    this.sub,
    this.height = 130,
    this.onTap,
    this.state = AuraTileState.normal,
    this.tooltip,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;
  final String? sub;
  final double height;
  final VoidCallback? onTap;
  final AuraTileState state;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(AuraRadius.panel);
    final Widget content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Container(
        padding: const EdgeInsets.all(AuraSpace.md),
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              accent.withValues(alpha: 0.26),
              accent.withValues(alpha: 0.07),
            ],
          ),
          border: Border.all(color: accent.withValues(alpha: 0.22)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            _TileIcon(icon: icon, accent: accent, state: state),
            Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AuraColors.textSecondary,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AuraColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                if (sub != null) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    sub!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AuraColors.textSecondary,
                        ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );

    return Tooltip(
      message: tooltip ?? '',
      excludeFromSemantics: tooltip == null,
      child: Semantics(
        button: onTap != null,
        enabled: onTap != null,
        label: onTap == null ? null : '$label: $value',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: content,
          ),
        ),
      ),
    );
  }
}

class _TileIcon extends StatelessWidget {
  const _TileIcon({
    required this.icon,
    required this.accent,
    required this.state,
  });

  final IconData icon;
  final Color accent;
  final AuraTileState state;

  @override
  Widget build(BuildContext context) {
    if (state == AuraTileState.loading) {
      return SizedBox.square(
        dimension: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(accent),
        ),
      );
    }
    return Icon(
      icon,
      size: 28,
      color: state == AuraTileState.unavailable
          ? AuraColors.textSecondary
          : accent,
    );
  }
}
