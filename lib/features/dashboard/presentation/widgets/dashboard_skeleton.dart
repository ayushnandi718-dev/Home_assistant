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
              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: AuraSpace.md,
                  mainAxisSpacing: AuraSpace.md,
                  mainAxisExtent: 152,
                ),
                itemCount: 6,
                itemBuilder: (BuildContext context, int index) =>
                    const _Block(height: 152),
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
