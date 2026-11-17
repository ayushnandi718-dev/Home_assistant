import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

enum AuraBannerTone { info, warning, privacy }

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

    return Container(
      padding: const EdgeInsets.all(AuraSpace.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AuraRadius.card),
        border: Border.all(color: color.withValues(alpha: 0.22)),
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
