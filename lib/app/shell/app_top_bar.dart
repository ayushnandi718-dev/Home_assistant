import 'package:aura_hub/app/navigation.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_logo.dart';
import 'package:aura_hub/shared/widgets/glass/glass_badge.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
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
    return GlassContainer(
      surface: AuraGlassSurface.chrome,
      radius: 0,
      showHighlight: false,
      height: compact ? 62 : 76,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? AuraSpace.md : AuraSpace.lg,
      ),
      border: const Border(
        bottom: BorderSide(color: AuraColors.border, width: 1),
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
          const _NotificationButton(),
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
      child: const GlassStatusBadge(
        label: 'Core not linked',
        color: AuraColors.warning,
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
      child: GlassStatusBadge(label: label, color: color),
    );
  }
}

class _NotificationButton extends ConsumerWidget {
  const _NotificationButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int unread = ref.watch(unreadNotificationCountProvider);
    return Badge(
      isLabelVisible: unread > 0,
      label: Text(
        '$unread',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AuraColors.onAccent,
        ),
      ),
      backgroundColor: AuraColors.warning,
      offset: const Offset(2, 2),
      child: Tooltip(
        message: 'Notifications',
        child: GlassContainer(
          surface: AuraGlassSurface.panel,
          width: 40,
          height: 40,
          radius: AuraRadius.control,
          blur: 0,
          fill: 0.42,
          showHighlight: false,
          padding: EdgeInsets.zero,
          onTap: () => context.go(AppRoutes.notifications),
          child: const Center(
            child: Icon(Icons.notifications_none_rounded, size: 20),
          ),
        ),
      ),
    );
  }
}

class _WorkspaceMenu extends ConsumerWidget {
  const _WorkspaceMenu({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final ProfileSession session = ref.watch(profileSessionProvider);
    final AuraProfile profile = session.profile;
    final bool unlocked = session.privateSessionActive;

    return PopupMenuButton<String>(
      tooltip: 'Workspace',
      color: const Color(0xEE182334),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AuraRadius.control),
        side: const BorderSide(color: AuraColors.border),
      ),
      offset: const Offset(0, 48),
      onSelected: (String value) => context.go(value),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<String>>[
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(profile.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AuraColors.textPrimary,
                  )),
              const SizedBox(height: 2),
              Text(profile.description,
                  style: const TextStyle(
                      fontSize: 11, color: AuraColors.textSecondary)),
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
      child: GlassContainer(
        surface: AuraGlassSurface.panel,
        radius: AuraRadius.pill,
        blur: 0,
        fill: 0.45,
        showHighlight: false,
        padding: const EdgeInsets.symmetric(
          horizontal: AuraSpace.xs,
          vertical: AuraSpace.xs - 2,
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
              child: Text(
                profile.label.substring(0, 1),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AuraColors.onAccent,
                ),
              ),
            ),
            if (!compact) ...<Widget>[
              const SizedBox(width: AuraSpace.sm),
              Text(profile.label, style: text.titleSmall),
              const SizedBox(width: AuraSpace.xxs),
              Icon(
                unlocked ? Icons.lock_open_outlined : Icons.lock_outline,
                size: 14,
                color: unlocked ? AuraColors.success : AuraColors.textSecondary,
              ),
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
