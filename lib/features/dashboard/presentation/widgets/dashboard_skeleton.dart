import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

class DashboardSkeleton extends StatelessWidget {
  const DashboardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading dashboard data',
      child: Column(
        children: <Widget>[
          _Block(height: 72),
          const SizedBox(height: AuraSpace.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = constraints.maxWidth >= 1180
                  ? 3
                  : constraints.maxWidth >= 560
                      ? 2
                      : 1;
              final double availableWidth = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : AuraBreakpoints.content.toDouble();
              final double tileWidth = columns == 1
                  ? availableWidth
                  : (availableWidth - AuraSpace.md * (columns - 1)) / columns;
              return Wrap(
                spacing: AuraSpace.md,
                runSpacing: AuraSpace.md,
                children: <Widget>[
                  for (int index = 0; index < 6; index++)
                    SizedBox(
                      width: tileWidth,
                      height: 152,
                      child: const _Block(height: 152),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: AuraSpace.md),
          const _Block(height: 320),
          const SizedBox(height: AuraSpace.md),
          const _Block(height: 240),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.height});

  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: AuraColors.elevated.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AuraRadius.card),
        border: Border.all(color: AuraColors.border.withValues(alpha: 0.5)),
      ),
    );
  }
}
