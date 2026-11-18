import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/notifications/domain/aura_notification.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Dashboard summary of the active workspace's real notifications.
class NotificationSummaryCard extends ConsumerWidget {
  const NotificationSummaryCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AuraNotification> notifications =
        ref.watch(activeNotificationsProvider);
    final int unread = ref.watch(unreadNotificationCountProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassContainer(
                width: 34,
                height: 34,
                padding: EdgeInsets.zero,
                radius: 10,
                blur: 0,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.primary.withValues(alpha: 0.3),
                child: const Icon(Icons.notifications_none_rounded,
                    size: 18, color: AuraColors.primary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text('Notifications', style: text.titleLarge),
              ),
              StatusPill(
                label: unread == 0 ? 'ALL READ' : '$unread UNREAD',
                color:
                    unread == 0 ? AuraColors.textSecondary : AuraColors.warning,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          if (notifications.isEmpty)
            Text(
              'No notifications from AURA services yet. Real changes, such as '
              'the local API going offline, will appear here.',
              style: text.bodyMedium,
            )
          else
            Column(
              children: <Widget>[
                for (final AuraNotification item in notifications.take(3))
                  Padding(
                    padding: const EdgeInsets.only(bottom: AuraSpace.sm),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(top: 6),
                          decoration: BoxDecoration(
                            color: _severityColor(item.severity),
                            shape: BoxShape.circle,
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: _severityColor(item.severity)
                                    .withValues(alpha: 0.5),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AuraSpace.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                item.title,
                                style: text.titleSmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                formatRelativeTime(item.timestamp),
                                style: text.labelSmall,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          const SizedBox(height: AuraSpace.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => context.go(AppRoutes.notifications),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('View notification centre'),
            ),
          ),
        ],
      ),
    );
  }

  Color _severityColor(NotificationSeverity severity) {
    switch (severity) {
      case NotificationSeverity.info:
        return AuraColors.primary;
      case NotificationSeverity.success:
        return AuraColors.success;
      case NotificationSeverity.warning:
        return AuraColors.warning;
      case NotificationSeverity.error:
        return AuraColors.danger;
    }
  }
}
