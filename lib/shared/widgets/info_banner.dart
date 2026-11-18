import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';

enum AuraBannerTone { info, warning, privacy }

/// Glass informational banner with a restrained tone accent.
class InfoBanner extends StatelessWidget {
  const InfoBanner({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    this.tone = AuraBannerTone.info,
    this.trailing,
  });

  final String title;
  final String message;
  final IconData icon;
  final AuraBannerTone tone;
  final Widget? trailing;

  Color get _color {
    switch (tone) {
      case AuraBannerTone.info:
        return AuraColors.primary;
      case AuraBannerTone.warning:
        return AuraColors.warning;
      case AuraBannerTone.privacy:
        return AuraColors.secondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = _color;
    final TextTheme text = Theme.of(context).textTheme;

    return GlassContainer(
      surface: AuraGlassSurface.panel,
      radius: AuraRadius.card,
      blur: 10,
      fill: 0.58,
      borderColor: color.withValues(alpha: 0.28),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[
          color.withValues(alpha: 0.14),
          AuraGlass.tint.withValues(alpha: 0.64),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  style: text.titleSmall?.copyWith(color: color),
                ),
                const SizedBox(height: AuraSpace.xxs),
                Text(message, style: text.bodyMedium),
              ],
            ),
          ),
          if (trailing != null) ...<Widget>[
            const SizedBox(width: AuraSpace.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}
