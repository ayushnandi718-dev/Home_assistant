import 'dart:async';

import 'package:aura_hub/app/navigation.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/ayush_unlock_dialog.dart';
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
    final bool compact =
        MediaQuery.sizeOf(context).width < AuraBreakpoints.mobile;
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
          // Small, actionable issue signal only on mobile Home. Diagnostics
          // remains the single place with the full explanation.
          if (compact && location == AppRoutes.dashboard)
            const _MobileIssueIndicator(),
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
          'from the Windows telemetry API and from any AI provider status.',
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
    final TelemetryApiState service = ref.watch(telemetryApiStateProvider);
    final bool showServiceState = switch (service.status) {
      TelemetryApiStatus.starting ||
      TelemetryApiStatus.reconnecting ||
      TelemetryApiStatus.startupFailed =>
        true,
      TelemetryApiStatus.online || TelemetryApiStatus.offline => false,
    };
    final String label =
        showServiceState ? service.status.label : connection.label;
    final Color color = showServiceState
        ? service.status == TelemetryApiStatus.startupFailed
            ? AuraColors.danger
            : AuraColors.warning
        : !connection.active
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

/// True only for real, device-relevant failures. A missing Windows telemetry
/// API on Android is expected and must not light this indicator.
final Provider<bool> _mobileIssueProvider = Provider<bool>((Ref ref) {
  final List<DiagnosticEvent> events = ref.watch(diagnosticEventsProvider);
  final bool deviceFailure = events.any(
    (DiagnosticEvent event) =>
        !event.succeeded &&
        (event.category == DiagnosticCategory.deviceDiscovery ||
            event.category == DiagnosticCategory.devicePairing ||
            event.category == DiagnosticCategory.deviceConnection),
  );
  if (deviceFailure) return true;

  if (ref.watch(deviceConnectionProvider).hasError) return true;
  if (ref.watch(devicePairingProvider).hasError) return true;
  if (ref.watch(deviceLinkProvider).status == DeviceLinkStatus.unavailable) {
    return true;
  }
  return false;
});

class _MobileIssueIndicator extends ConsumerWidget {
  const _MobileIssueIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(_mobileIssueProvider)) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(right: AuraSpace.xs),
      child: Tooltip(
        message: 'Diagnostics issue',
        child: GlassContainer(
          surface: AuraGlassSurface.panel,
          width: 40,
          height: 40,
          radius: AuraRadius.control,
          blur: 0,
          fill: 0.42,
          showHighlight: false,
          padding: EdgeInsets.zero,
          onTap: () => context.go(AppRoutes.diagnostics),
          child: const Center(
            child: Icon(
              Icons.error_outline_rounded,
              size: 20,
              color: AuraColors.warning,
            ),
          ),
        ),
      ),
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

/// Actions exposed by the navbar workspace chip.
enum _WorkspaceAction { family, ayush, manageProfiles, settings }

class _WorkspaceMenu extends ConsumerWidget {
  const _WorkspaceMenu({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final ProfileSession session = ref.watch(profileSessionProvider);
    final AuraProfile profile = session.profile;
    final bool unlocked = session.privateSessionActive;

    return PopupMenuButton<_WorkspaceAction>(
      tooltip: 'Workspace',
      color: const Color(0xEE182334),
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AuraRadius.control),
        side: const BorderSide(color: AuraColors.border),
      ),
      offset: const Offset(0, 48),
      onSelected: (_WorkspaceAction action) =>
          _onSelected(context, ref, action),
      itemBuilder: (BuildContext context) => <PopupMenuEntry<_WorkspaceAction>>[
        PopupMenuItem<_WorkspaceAction>(
          enabled: false,
          child: _MenuHeader(profile: profile),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_WorkspaceAction>(
          value: _WorkspaceAction.family,
          child: _ProfileMenuTile(
            profile: AuraProfile.family,
            active: profile == AuraProfile.family,
          ),
        ),
        PopupMenuItem<_WorkspaceAction>(
          value: _WorkspaceAction.ayush,
          child: _ProfileMenuTile(
            profile: AuraProfile.ayush,
            active: unlocked,
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<_WorkspaceAction>(
          value: _WorkspaceAction.manageProfiles,
          child: Text('Manage profiles & security'),
        ),
        const PopupMenuItem<_WorkspaceAction>(
          value: _WorkspaceAction.settings,
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
            _ProfileAvatar(profile: profile, size: 30),
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

  void _onSelected(
    BuildContext context,
    WidgetRef ref,
    _WorkspaceAction action,
  ) {
    // Read the session at action time: a switch made while the menu was open
    // must not leave a stale profile label behind.
    final ProfileSession session = ref.read(profileSessionProvider);
    switch (action) {
      case _WorkspaceAction.family:
        if (session.profile != AuraProfile.family) {
          ref.read(profileSessionProvider.notifier).openFamily();
        }
        break;
      case _WorkspaceAction.ayush:
        if (!session.privateSessionActive) {
          unawaited(_requestAyushUnlock(context));
        }
        break;
      case _WorkspaceAction.manageProfiles:
        context.go(AppRoutes.profiles);
        break;
      case _WorkspaceAction.settings:
        context.go(AppRoutes.settings);
        break;
    }
  }

  Future<void> _requestAyushUnlock(BuildContext context) async {
    // Let the popup route finish dismissing before the PIN dialog opens.
    await Future<void>.delayed(Duration.zero);
    if (!context.mounted) return;
    // The controller updates the session only on a successful unlock, so a
    // cancelled or rejected PIN leaves the current workspace untouched.
    await showAyushUnlockDialog(context: context);
  }
}

class _MenuHeader extends StatelessWidget {
  const _MenuHeader({required this.profile});

  final AuraProfile profile;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          profile.label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AuraColors.textPrimary,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          'Active profile',
          style: TextStyle(fontSize: 11, color: AuraColors.textSecondary),
        ),
      ],
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  const _ProfileMenuTile({required this.profile, required this.active});

  final AuraProfile profile;
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        _ProfileAvatar(profile: profile, size: 30),
        const SizedBox(width: AuraSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                profile.label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AuraColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                profile == AuraProfile.ayush
                    ? 'Private workspace · PIN required'
                    : 'Shared household workspace',
                style: const TextStyle(
                    fontSize: 11, color: AuraColors.textSecondary),
              ),
            ],
          ),
        ),
        if (active)
          const Icon(Icons.check_rounded, size: 17, color: AuraColors.success),
      ],
    );
  }
}

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({required this.profile, required this.size});

  static const String _ayushAvatar = 'assets/avatars/ayush.webp';
  static const String _familyAvatar = 'assets/avatars/family.webp';

  final AuraProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool isPrivate = profile == AuraProfile.ayush;
    final String avatar = isPrivate ? _ayushAvatar : _familyAvatar;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: (isPrivate ? AuraColors.secondary : AuraColors.primary)
              .withValues(alpha: 0.55),
          width: 1.2,
        ),
      ),
      child: ClipOval(
        child: Image.asset(
          avatar,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.high,
          errorBuilder: (_, __, ___) =>
              _InitialAvatar(profile: profile, size: size),
        ),
      ),
    );
  }
}

class _InitialAvatar extends StatelessWidget {
  const _InitialAvatar({required this.profile, required this.size});

  final AuraProfile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final bool isPrivate = profile == AuraProfile.ayush;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isPrivate
              ? const <Color>[AuraColors.secondary, AuraColors.primary]
              : const <Color>[AuraColors.primary, AuraColors.secondary],
        ),
        borderRadius: BorderRadius.circular(AuraRadius.pill),
      ),
      child: Text(
        profile.label.substring(0, 1),
        style: TextStyle(
          fontSize: size * 0.44,
          fontWeight: FontWeight.w700,
          color: AuraColors.onAccent,
        ),
      ),
    );
  }
}
