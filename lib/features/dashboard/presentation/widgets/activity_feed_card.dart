import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

IconData _iconFor(ActivityCategory category) {
  switch (category) {
    case ActivityCategory.device:
      return Icons.devices_other_outlined;
    case ActivityCategory.security:
      return Icons.shield_outlined;
    case ActivityCategory.integration:
      return Icons.extension_outlined;
    case ActivityCategory.system:
      return Icons.terminal_rounded;
  }
}

class ActivityFeedCard extends StatelessWidget {
  const ActivityFeedCard({super.key, required this.events});

  final List<ActivityEvent> events;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('ACTIVITY', style: text.labelMedium),
                    const SizedBox(height: AuraSpace.xxs),
                    Text('Recent system events', style: text.titleLarge),
                  ],
                ),
              ),
              const StatusPill(label: 'DEMO EVENTS', color: AuraColors.warning),
            ],
          ),
          const SizedBox(height: AuraSpace.lg),
          if (events.isEmpty)
            Padding(
              padding: const EdgeInsets.all(AuraSpace.lg),
              child: Text('No activity has been recorded.',
                  style: text.bodyMedium),
            )
          else
            Column(
              children: <Widget>[
                for (int index = 0; index < events.length; index++)
                  _ActivityRow(
                      event: events[index], isLast: index == events.length - 1),
              ],
            ),
        ],
      ),
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event, required this.isLast});

  final ActivityEvent event;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color color = event.severity == ActivitySeverity.warning
        ? AuraColors.warning
        : event.severity == ActivitySeverity.error
            ? AuraColors.danger
            : AuraColors.primary;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SizedBox(
            width: 36,
            child: Column(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    _iconFor(event.category),
                    size: 16,
                    color: color,
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 1,
                      color: AuraColors.border,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                bottom: isLast ? 0 : AuraSpace.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          event.title,
                          style: text.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: AuraSpace.sm),
                      Text(
                        formatRelativeTime(event.timestamp),
                        style: text.labelSmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: AuraSpace.xxs),
                  Text(
                    event.detail,
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
