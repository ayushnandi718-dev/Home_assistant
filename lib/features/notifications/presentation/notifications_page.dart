import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/notifications/domain/aura_notification.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Central notification centre for the active workspace.
class NotificationsPage extends ConsumerWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AuraNotification> notifications =
        ref.watch(activeNotificationsProvider);
    final AuraProfile profile = ref.watch(activeProfileProvider);
    final NotificationCenter center =
        ref.read(activeNotificationCenterProvider);
    final int unread = ref.watch(unreadNotificationCountProvider);

    return AuraScrollArea(
      padding: EdgeInsets.fromLTRB(
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.lg,
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageHeader(
                eyebrow: 'System / ${profile.label}',
                title: 'Notification Centre',
                description:
                    'Real events from AURA Hub services, stored separately for each workspace.',
                icon: Icons.notifications_active_outlined,
                trailing: Wrap(
                  spacing: AuraSpace.xs,
                  runSpacing: AuraSpace.xs,
                  children: <Widget>[
                    OutlinedButton.icon(
                      onPressed: unread == 0 ? null : center.markAllRead,
                      icon: const Icon(Icons.done_all_rounded, size: 16),
                      label: const Text('Mark all read'),
                    ),
                    OutlinedButton.icon(
                      onPressed: notifications.isEmpty ? null : center.clear,
                      icon: const Icon(Icons.delete_outline_rounded, size: 16),
                      label: const Text('Clear'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              if (notifications.isEmpty)
                SurfaceCard(
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.notifications_off_outlined,
                          size: 34, color: AuraColors.textSecondary),
                      const SizedBox(height: AuraSpace.md),
                      Text(
                        'No notifications yet',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: AuraSpace.xs),
                      Text(
                        'Notifications appear here only when AURA services '
                        'report a real change, such as the local API going '
                        'offline or recovering.',
                        style: Theme.of(context).textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                )
              else
                Column(
                  children: <Widget>[
                    for (final AuraNotification item in notifications)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AuraSpace.sm),
                        child: _NotificationTile(item: item, center: center),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.center});

  final AuraNotification item;
  final NotificationCenter center;

  Color get _color {
    switch (item.severity) {
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

  IconData get _icon {
    switch (item.severity) {
      case NotificationSeverity.info:
        return Icons.info_outline_rounded;
      case NotificationSeverity.success:
        return Icons.check_circle_outline_rounded;
      case NotificationSeverity.warning:
        return Icons.warning_amber_rounded;
      case NotificationSeverity.error:
        return Icons.error_outline_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      borderColor: item.isRead ? null : _color.withValues(alpha: 0.4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(_icon, size: 20, color: _color),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        item.title,
                        style: text.titleSmall?.copyWith(
                          fontWeight:
                              item.isRead ? FontWeight.w500 : FontWeight.w700,
                        ),
                      ),
                    ),
                    Text(
                      formatRelativeTime(item.timestamp),
                      style: text.labelSmall,
                    ),
                  ],
                ),
                const SizedBox(height: AuraSpace.xxs),
                Text(item.body, style: text.bodySmall),
                const SizedBox(height: AuraSpace.xxs),
                Text(
                  '${item.source.name.toUpperCase()}  ·  ${item.severity.name.toUpperCase()}',
                  style: text.labelSmall?.copyWith(
                    color: AuraColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AuraSpace.sm),
          Column(
            children: <Widget>[
              if (!item.isRead)
                IconButton(
                  tooltip: 'Mark read',
                  onPressed: () => center.markRead(item.id),
                  icon: const Icon(Icons.done_rounded, size: 18),
                ),
              IconButton(
                tooltip: 'Dismiss',
                onPressed: () => center.dismiss(item.id),
                icon: const Icon(Icons.close_rounded, size: 18),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
