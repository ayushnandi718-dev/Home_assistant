import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.eyebrow,
    required this.title,
    this.description,
    this.icon,
    this.accent,
    this.trailing,
    this.compact = false,
  });

  final String eyebrow;
  final String title;
  final String? description;
  final IconData? icon;
  final Color? accent;
  final Widget? trailing;

  /// Collapses explanatory copy and keeps trailing controls on a single
  /// horizontally scrollable row. Used while the keyboard is open so the
  /// page does not compete with the text field for vertical space.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color resolvedAccent = accent ?? AuraPaletteTheme.of(context).primary;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < 620;
        final Widget heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              GlassContainer(
                width: compact ? 32 : 46,
                height: compact ? 32 : 46,
                padding: EdgeInsets.zero,
                radius: 14,
                blur: 0,
                fill: 0.55,
                showHighlight: false,
                borderColor: resolvedAccent.withValues(alpha: 0.32),
                child:
                    Icon(icon, size: compact ? 18 : 22, color: resolvedAccent),
              ),
              SizedBox(width: compact ? AuraSpace.sm : AuraSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (!compact)
                    Text(
                      eyebrow.toUpperCase(),
                      style: text.labelMedium?.copyWith(color: resolvedAccent),
                    ),
                  SizedBox(height: compact ? AuraSpace.xxs : AuraSpace.xs),
                  Text(
                    title,
                    style: compact ? text.titleLarge : text.headlineMedium,
                  ),
                  if (description != null && !compact) ...<Widget>[
                    const SizedBox(height: AuraSpace.sm),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 680),
                      child: Text(description!, style: text.bodyMedium),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );

        if (trailing == null) {
          return heading;
        }
        // Functionally identical on desktop: only compact pages take the
        // single-row scrollable path.
        final Widget resolvedTrailing = compact
            ? SizedBox(
                height: 44,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.hardEdge,
                  child: trailing!,
                ),
              )
            : trailing!;

        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              heading,
              SizedBox(height: compact ? AuraSpace.xs : AuraSpace.md),
              resolvedTrailing,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: AuraSpace.md),
            resolvedTrailing,
          ],
        );
      },
    );
  }
}
