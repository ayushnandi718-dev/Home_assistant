import 'package:aura_hub/app/navigation.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/shared/widgets/aura_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

class AppTopBar extends ConsumerWidget {
  const AppTopBar({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool compact = MediaQuery.sizeOf(context).width < 700;
    final AuraDestination? destination = destinationForLocation(location);
    final TextTheme text = Theme.of(context).textTheme;
    final DashboardConnectionStatus connection =
        ref.watch(dashboardStatusProvider);
    final List<ActivityEvent> events = connection.activity;

    return Container(
      height: compact ? 62 : 76,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AuraSpace.md : AuraSpace.lg,
      ),
      decoration: const BoxDecoration(
        color: Color(0x99101722),
        border: Border(bottom: BorderSide(color: AuraColors.border, width: 1)),
      ),
      child: Row(
        children: <Widget>[
          if (compact) ...<Widget>[
            const AuraLogo(size: 30),
            const SizedBox(width: AuraSpace.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(
                  destination == null
                      ? AppInfo.name.toUpperCase()
                      : '${AppInfo.name.toUpperCase()} / ${sectionLabel(destination.section)}',
                  style: text.labelSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  destination?.label ?? AppInfo.name,
                  style: compact ? text.titleMedium : text.titleLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: AuraSpace.sm),
          if (!compact) const _CoreStatusChip(),
          if (!compact) const SizedBox(width: AuraSpace.xs),
          if (!compact) const _HostApiStatusChip(),
          if (!compact) const SizedBox(width: AuraSpace.sm),
          _NotificationButton(events: events),
          const SizedBox(width: AuraSpace.xs),
          _WorkspaceMenu(compact: compact),
        ],
      ),
    );
  }
}

class _CoreStatusChip extends StatelessWidget {
  const _CoreStatusChip();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          'AURA ESP32 hardware and backend are not linked. This is separate '
          'from the Windows telemetry API.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AuraSpace.sm,
          vertical: AuraSpace.xs,
        ),
        decoration: BoxDecoration(
          color: AuraColors.warning.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AuraRadius.pill),
          border: Border.all(color: AuraColors.warning.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: AuraColors.warning,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AuraSpace.xs),
            Text(
              'Core not linked',
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: AuraColors.warning),
            ),
          ],
        ),
      ),
    );
  }
}

/// Reports only the local Windows telemetry API. It is deliberately separate
/// from the AURA Core hardware chip above.
class _HostApiStatusChip extends ConsumerWidget {
  const _HostApiStatusChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DashboardConnectionStatus connection =
        ref.watch(dashboardStatusProvider);
    final String label = connection.label;
    final Color color = !connection.active
        ? AuraColors.textSecondary
        : connection.stale || !connection.localApiOnline
            ? AuraColors.warning
            : AuraColors.success;

    return Tooltip(
      message: 'Local Windows telemetry API only. Not an AURA device link.',
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AuraSpace.sm,
          vertical: AuraSpace.xs,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AuraRadius.pill),
          border: Border.all(color: color.withValues(alpha: 0.24)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: AuraSpace.xs),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.events});

  final List<ActivityEvent> events;

  @override
  Widget build(BuildContext context) {
    return Badge(
      label: Text(
        '${events.length}',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AuraColors.onAccent,
        ),
      ),
      backgroundColor: AuraColors.warning,
      offset: const Offset(2, 2),
      child: IconButton(
        tooltip: 'Notifications',
        onPressed: () => _showNotifications(context, events),
        icon: const Icon(Icons.notifications_none_rounded, size: 20),
      ),
    );
  }

  void _showNotifications(BuildContext context, List<ActivityEvent> events) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        final TextTheme text = Theme.of(dialogContext).textTheme;
        return Dialog(
          backgroundColor: AuraColors.card,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AuraRadius.panel),
            side: const BorderSide(color: AuraColors.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Padding(
              padding: const EdgeInsets.all(AuraSpace.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('NOTIFICATIONS', style: text.labelMedium),
                            const SizedBox(height: AuraSpace.xxs),
                            Text('Recent host events', style: text.titleLarge),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: AuraSpace.md),
                  if (events.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(AuraSpace.md),
                      child: Text(
                        'No notifications are available until AURA Core is connected.',
                        style: text.bodyMedium,
                      ),
                    )
                  else
                    Column(
                      children: <Widget>[
                        for (final ActivityEvent event in events.take(4))
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AuraSpace.sm),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Icon(
                                  Icons.circle,
                                  size: 7,
                                  color:
                                      event.severity == ActivitySeverity.warning
                                          ? AuraColors.warning
                                          : AuraColors.primary,
                                ),
                                const SizedBox(width: AuraSpace.sm),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Text(event.title, style: text.titleSmall),
                                      const SizedBox(height: 2),
                                      Text(
                                        formatRelativeTime(event.timestamp),
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
                  const Divider(height: AuraSpace.lg),
                  Text(
                    'Delivery from the real AURA Core service arrives with backend integration.',
                    style: text.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _WorkspaceMenu extends StatelessWidget {
  const _WorkspaceMenu({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return PopupMenuButton<String>(
      tooltip: 'Workspace',
      color: AuraColors.elevated,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AuraRadius.control),
        side: const BorderSide(color: AuraColors.border),
      ),
      offset: const Offset(0, 48),
      onSelected: (String value) => context.go(value),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        const PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('AYUSH',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AuraColors.textPrimary,
                  )),
              SizedBox(height: 2),
              Text('Private - PIN required',
                  style:
                      TextStyle(fontSize: 11, color: AuraColors.textSecondary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: AppRoutes.profiles,
          child: Text('Manage profiles & security'),
        ),
        const PopupMenuItem<String>(
          value: AppRoutes.settings,
          child: Text('App settings'),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AuraSpace.xs,
          vertical: AuraSpace.xs - 2,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AuraRadius.pill),
          border: Border.all(color: AuraColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: <Color>[AuraColors.primary, AuraColors.secondary],
                ),
                borderRadius: BorderRadius.circular(AuraRadius.pill),
              ),
              child: const Text(
                'A',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AuraColors.onAccent,
                ),
              ),
            ),
            if (!compact) ...<Widget>[
              const SizedBox(width: AuraSpace.sm),
              Text('Ayush', style: text.titleSmall),
              const SizedBox(width: AuraSpace.xxs),
              Icon(Icons.keyboard_arrow_down_rounded,
                  size: 16, color: AuraColors.textSecondary),
            ],
          ],
        ),
      ),
    );
  }
}
