import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';

/// Consistent section heading with an optional glass icon tile and trailing
/// control. Used by pages that compose their own sections instead of cards.
class GlassSectionHeader extends StatelessWidget {
  const GlassSectionHeader({
    super.key,
    this.eyebrow,
    required this.title,
    this.subtitle,
    this.icon,
    this.trailing,
    this.accent = AuraColors.primary,
  });

  final String? eyebrow;
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? trailing;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (icon != null) ...<Widget>[
          GlassContainer(
            width: 42,
            height: 42,
            padding: EdgeInsets.zero,
            radius: AuraRadius.control,
            fill: 0.5,
            blur: 8,
            showHighlight: false,
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(width: AuraSpace.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              if (eyebrow != null)
                Text(
                  eyebrow!.toUpperCase(),
                  style: text.labelMedium?.copyWith(color: accent),
                ),
              Text(title, style: text.titleLarge),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: AuraSpace.xxs),
                Text(subtitle!, style: text.bodySmall),
              ],
            ],
          ),
        ),
        if (trailing != null) ...<Widget>[
          const SizedBox(width: AuraSpace.sm),
          trailing!,
        ],
      ],
    );
  }
}
