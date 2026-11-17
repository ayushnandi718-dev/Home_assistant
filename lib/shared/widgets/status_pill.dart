import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.color = AuraColors.textSecondary,
    this.icon,
    this.showDot = true,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color color;
  final bool showDot;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? AuraSpace.xs : AuraSpace.sm,
        vertical: dense ? AuraSpace.xxs : AuraSpace.xs - 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AuraRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null)
            Padding(
              padding: const EdgeInsets.only(right: AuraSpace.xs - 2),
              child: Icon(icon, size: dense ? 12 : 13, color: color),
            )
          else if (showDot)
            Padding(
              padding: const EdgeInsets.only(right: AuraSpace.xs - 2),
              child: Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'Inter',
              fontSize: dense ? 9.5 : 11,
              fontWeight: FontWeight.w600,
              color: color,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
