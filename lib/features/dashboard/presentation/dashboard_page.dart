import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/telemetry_history.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/activity_feed_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/dashboard_customize_dialog.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/dashboard_skeleton.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/device_spotlight_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/live_data_notice.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/overview_grid.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/quick_actions_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/source_health_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/telemetry_history_card.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/features/notifications/presentation/widgets/notification_summary_card.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/api_startup_guide.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

String _stateKey(AsyncValue<DashboardSnapshot> state) => state.when(
      data: (DashboardSnapshot _) => 'data',
      loading: () => 'loading',
      error: (Object _, StackTrace __) => 'error',
    );

class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DashboardSnapshot> state =
        ref.watch(dashboardSnapshotProvider);
    final double width = MediaQuery.sizeOf(context).width;
    final double padding = pageHorizontalPadding(width);
    final String apiUrl = ref.watch(auraApiClientProvider).displayUrl;
    final DateTime sampledAt = state.valueOrNull?.generatedAt ?? DateTime.now();
    final bool stale = state.valueOrNull?.stale ?? false;
    final bool localApiOnline = state.valueOrNull?.localApiOnline ?? false;
    final bool auraDeviceLinked =
        state.valueOrNull?.coreLink == CoreLinkState.linked;
    final DashboardConnectionStatus connection =
        ref.watch(dashboardStatusProvider);
    final ApiHealth? apiHealth = ref.watch(apiHealthProvider);
    final AppSettings settings = ref.watch(appSettingsProvider);
    final TelemetryHistory history = ref.watch(telemetryHistoryProvider);
    final DashboardSnapshot? snapshot = state.valueOrNull;
    final DashboardLayout layout = ref.watch(dashboardLayoutProvider);
    final AuraProfile profile = ref.watch(activeProfileProvider);

    return AuraScrollArea(
      padding:
          EdgeInsets.fromLTRB(padding, AuraSpace.lg, padding, AuraSpace.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              GreetingHeader(
                isRefreshing: state.isLoading,
                onRefresh: () => ref.read(dashboardSyncProvider).refresh(),
                greetingName: profile == AuraProfile.ayush
                    ? profile.label.toLowerCase()
                    : '',
                onCustomize: () => showGlassDialog<void>(
                  context: context,
                  child: const DashboardCustomizeDialog(),
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              LiveDataNotice(
                apiUrl: apiUrl,
                generatedAt: sampledAt,
                stale: stale,
                localApiOnline: localApiOnline,
                auraDeviceLinked: auraDeviceLinked,
              ),
              const SizedBox(height: AuraSpace.md),
              SourceHealthCard(
                connection: connection,
                sampler: snapshot?.samplerHealth,
                coreLink: snapshot?.coreLink ?? CoreLinkState.notLinked,
                deviceCount: snapshot?.devices.length ?? 0,
                apiHealth: apiHealth,
              ),
              const SizedBox(height: AuraSpace.lg),
              AnimatedSwitcher(
                duration: AuraMotion.of(context, AuraMotion.medium),
                switchInCurve: AuraMotion.enter,
                switchOutCurve: AuraMotion.exit,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.008),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: KeyedSubtree(
                  key: ValueKey<String>(_stateKey(state)),
                  child: state.when(
                    data: (DashboardSnapshot snapshot) => _DashboardBody(
                      snapshot: snapshot,
                      history: history,
                      retentionLabel: '${settings.historyRetentionMinutes} min',
                      layout: layout,
                    ),
                    loading: () => const DashboardSkeleton(),
                    error: (Object error, StackTrace stack) => _ErrorState(
                      message: error.toString(),
                      onRetry: () => ref.read(dashboardSyncProvider).refresh(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({
    required this.snapshot,
    required this.history,
    required this.retentionLabel,
    required this.layout,
  });

  final DashboardSnapshot snapshot;
  final TelemetryHistory history;
  final String retentionLabel;
  final DashboardLayout layout;

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 1180;

    // Only visible widgets are rendered, in the exact order the user chose.
    final List<DashboardWidgetId> visible = layout.widgets
        .where((DashboardWidgetConfig item) => item.visible)
        .map((DashboardWidgetConfig item) => item.id)
        .toList(growable: false);

    final List<Widget> cards = <Widget>[];
    for (int index = 0; index < visible.length; index++) {
      final DashboardWidgetId id = visible[index];

      // Preserve the existing side-by-side device/actions layout on wide
      // screens when those two widgets remain adjacent after customization.
      if (wide &&
          id == DashboardWidgetId.spotlight &&
          index + 1 < visible.length &&
          visible[index + 1] == DashboardWidgetId.quickActions) {
        cards.add(
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: DeviceSpotlightCard(devices: snapshot.devices),
              ),
              const SizedBox(width: AuraSpace.lg),
              const Expanded(flex: 2, child: QuickActionsCard()),
            ],
          ),
        );
        index++;
        continue;
      }

      cards.add(_cardFor(id));
    }

    if (cards.isEmpty) {
      return const _EmptyLayoutState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        for (int index = 0; index < cards.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(height: AuraSpace.lg),
          cards[index],
        ],
      ],
    );
  }

  Widget _cardFor(DashboardWidgetId id) {
    switch (id) {
      case DashboardWidgetId.overview:
        return OverviewGrid(snapshot: snapshot);
      case DashboardWidgetId.history:
        return TelemetryHistoryCard(
          samples: history.samples,
          revision: history.revision,
          capacity: history.maxSamples,
          retentionLabel: retentionLabel,
        );
      case DashboardWidgetId.spotlight:
        return DeviceSpotlightCard(devices: snapshot.devices);
      case DashboardWidgetId.quickActions:
        return const QuickActionsCard();
      case DashboardWidgetId.activity:
        return ActivityFeedCard(events: snapshot.activity);
      case DashboardWidgetId.notifications:
        return const NotificationSummaryCard();
    }
  }
}

/// Shown when the user has hidden every optional widget. Provenance banners
/// above the body stay visible, so hiding widgets can never hide data source
/// information.
class _EmptyLayoutState extends StatelessWidget {
  const _EmptyLayoutState();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Column(
        children: <Widget>[
          Icon(Icons.dashboard_customize_outlined,
              size: 34, color: AuraColors.textSecondary),
          const SizedBox(height: AuraSpace.md),
          Text('Dashboard widgets hidden',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AuraSpace.xs),
          Text(
            'Use the Customize button in the header to show widgets again. '
            'Live-data and health banners remain visible at all times.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        children: <Widget>[
          Icon(Icons.error_outline_rounded, size: 34, color: AuraColors.danger),
          const SizedBox(height: AuraSpace.md),
          Text('Could not load dashboard data', style: text.titleLarge),
          const SizedBox(height: AuraSpace.xs),
          Text(message, style: text.bodySmall, textAlign: TextAlign.center),
          const SizedBox(height: AuraSpace.md),
          Text(
            'Start the local API with scripts\\start_aura_api.ps1 in '
            'PowerShell, then select Retry. This checks the Windows host only; '
            'it does not pair an AURA device.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AuraSpace.md),
          const ApiStartupGuide(compact: true),
          const SizedBox(height: AuraSpace.lg),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
