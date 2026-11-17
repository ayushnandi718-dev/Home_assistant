import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class GreetingHeader extends StatelessWidget {
  const GreetingHeader({
    super.key,
    required this.onRefresh,
    required this.isRefreshing,
  });

  final VoidCallback onRefresh;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final DateTime now = DateTime.now();

    final Widget heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          formatDateHeader(now).toUpperCase(),
          style: text.labelMedium?.copyWith(color: AuraColors.primary),
        ),
        const SizedBox(height: AuraSpace.xs),
        Text('${greetingForHour(now.hour)}, Ayush', style: text.displayLarge),
        const SizedBox(height: AuraSpace.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: Text(
            'Here is the current state of your AURA workspace.',
            style: text.bodyMedium,
          ),
        ),
      ],
    );

    final Widget actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Tooltip(
          message: 'Reload dashboard data',
          child: IconButton(
            onPressed: isRefreshing ? null : onRefresh,
            style: IconButton.styleFrom(
              backgroundColor: AuraColors.elevated,
              foregroundColor: AuraColors.primary,
            ),
            icon: AnimatedSwitcher(
              duration: AuraMotion.of(context, AuraMotion.fast),
              switchInCurve: AuraMotion.enter,
              switchOutCurve: AuraMotion.exit,
              transitionBuilder: (Widget child, Animation<double> animation) {
                return ScaleTransition(
                  scale: Tween<double>(begin: 0.7, end: 1).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: isRefreshing
                  ? const SizedBox(
                      key: ValueKey<bool>(true),
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(
                      Icons.refresh_rounded,
                      key: ValueKey<bool>(false),
                      size: 18,
                    ),
            ),
          ),
        ),
        const SizedBox(width: AuraSpace.sm),
        FilledButton.icon(
          onPressed: () => context.go(AppRoutes.devices),
          icon: const Icon(Icons.add_rounded, size: 17),
          label: const Text('Add device'),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              heading,
              const SizedBox(height: AuraSpace.lg),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            Expanded(child: heading),
            const SizedBox(width: AuraSpace.lg),
            actions,
          ],
        );
      },
    );
  }
}
