import 'package:aura_hub/core/theme/aura_colors.dart';
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
    this.accent = AuraColors.primary,
    this.trailing,
  });

  final String eyebrow;
  final String title;
  final String? description;
  final IconData? icon;
  final Color accent;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool stacked = constraints.maxWidth < 620;
        final Widget heading = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              GlassContainer(
                width: 46,
                height: 46,
                padding: EdgeInsets.zero,
                radius: 14,
                blur: 0,
                fill: 0.55,
                showHighlight: false,
                borderColor: accent.withValues(alpha: 0.32),
                child: Icon(icon, size: 22, color: accent),
              ),
              const SizedBox(width: AuraSpace.md),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    eyebrow.toUpperCase(),
                    style: text.labelMedium?.copyWith(color: accent),
                  ),
                  const SizedBox(height: AuraSpace.xs),
                  Text(title, style: text.headlineMedium),
                  if (description != null) ...<Widget>[
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
        if (stacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              heading,
              const SizedBox(height: AuraSpace.md),
              trailing!,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: AuraSpace.md),
            trailing!,
          ],
        );
      },
    );
  }
}
