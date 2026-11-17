import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/aura_logo.dart';
import 'package:flutter/material.dart';

/// Pure illustration of the 4.3 inch AURA panel.
///
/// It never displays Windows telemetry: showing PC readings inside a device
/// mock-up would imply AURA hardware is connected and reporting.
class DeviceFrame extends StatelessWidget {
  const DeviceFrame({super.key});

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: AspectRatio(
        aspectRatio: 1.48,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[AuraColors.elevated, AuraColors.backgroundDeep],
            ),
            border: Border.all(color: AuraColors.border),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: AuraColors.primary.withValues(alpha: 0.10),
                blurRadius: 44,
                spreadRadius: -8,
              ),
            ],
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 0.9,
                colors: <Color>[
                  AuraColors.primary.withValues(alpha: 0.12),
                  const Color(0xFF080C14),
                ],
              ),
              border: Border.all(
                color: AuraColors.primary.withValues(alpha: 0.14),
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                const AuraLogo(size: 52),
                const SizedBox(height: AuraSpace.sm),
                Text(
                  'AURA',
                  style: text.titleMedium?.copyWith(letterSpacing: 3.5),
                ),
                const SizedBox(height: AuraSpace.xs),
                Text(
                  'ILLUSTRATION ONLY',
                  style: text.labelSmall?.copyWith(color: AuraColors.primary),
                ),
                const SizedBox(height: AuraSpace.xxs),
                Text(
                  'NO LIVE DEVICE FEED',
                  style: text.labelSmall
                      ?.copyWith(color: AuraColors.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
