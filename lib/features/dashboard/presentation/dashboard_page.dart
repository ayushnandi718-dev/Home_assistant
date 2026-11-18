import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/telemetry_history.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_grid.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/activity_feed_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/dashboard_widget_studio_dialog.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/dashboard_skeleton.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/device_spotlight_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/live_data_notice.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/overview_grid.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/quick_actions_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/source_health_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/telemetry_history_card.dart';
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

/// Static shell for the dashboard.
///
/// No provider is watched here: every subscription lives in the smallest leaf
/// that displays its value, so a telemetry sample never rebuilds the header,
/// provenance chrome or scroll structure.
class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final double padding = pageHorizontalPadding(width);

    return Stack(
      children: <Widget>[
        const Positioned.fill(
          child: IgnorePointer(child: _DashboardAmbient()),
        ),
        Positioned.fill(
          child: AuraScrollArea(
            padding: EdgeInsets.fromLTRB(
                padding, AuraSpace.lg, padding, AuraSpace.xxl),
            child: Center(
              child: ConstrainedBox(
                constraints:
                    const BoxConstraints(maxWidth: AuraBreakpoints.content),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _DashboardHeader(),
                    SizedBox(height: AuraSpace.lg),
                    _DashboardStatusSection(),
                    SizedBox(height: AuraSpace.lg),
                    _DashboardBodySwitcher(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Rebuilds only when the workspace or initial loading state changes.
class _DashboardHeader extends ConsumerWidget {
  const _DashboardHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuraProfile profile = ref.watch(activeProfileProvider);
    final bool isRefreshing = ref.watch(
      dashboardSnapshotProvider.select(
        (AsyncValue<DashboardSnapshot> state) => state.isLoading,
      ),
    );

    return RepaintBoundary(
      child: GreetingHeader(
        isRefreshing: isRefreshing,
        onRefresh: () => ref.read(dashboardSyncProvider).refresh(),
        greetingName:
            profile == AuraProfile.ayush ? profile.label.toLowerCase() : '',
        onCustomize: () => showGlassDialog<void>(
          context: context,
          child: const DashboardWidgetStudioDialog(),
        ),
      ),
    );
  }
}

/// Provenance and source-health strip. It must stay visible, and it is the
/// only place that follows the per-sample status fields.
class _DashboardStatusSection extends ConsumerWidget {
  const _DashboardStatusSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DashboardSnapshot> state =
        ref.watch(dashboardSnapshotProvider);
    final DashboardSnapshot? snapshot = state.valueOrNull;
    final DashboardConnectionStatus connection =
        ref.watch(dashboardStatusProvider);
    final String apiUrl = ref.watch(
      auraApiClientProvider.select(
        (AuraApiClient client) => client.displayUrl,
      ),
    );

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LiveDataNotice(
            apiUrl: apiUrl,
            generatedAt: snapshot?.generatedAt ?? DateTime.now(),
            stale: snapshot?.stale ?? false,
            localApiOnline: snapshot?.localApiOnline ?? false,
            auraDeviceLinked: snapshot?.coreLink == CoreLinkState.linked,
          ),
          const SizedBox(height: AuraSpace.md),
          SourceHealthCard(
            connection: connection,
            sampler: snapshot?.samplerHealth,
            coreLink: snapshot?.coreLink ?? CoreLinkState.notLinked,
            deviceCount: snapshot?.devices.length ?? 0,
          ),
        ],
      ),
    );
  }
}

/// The mutable body only. Keeping the switcher here prevents status and header
/// chrome from being torn down when a poll changes the snapshot identity.
class _DashboardBodySwitcher extends ConsumerWidget {
  const _DashboardBodySwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<DashboardSnapshot> state =
        ref.watch(dashboardSnapshotProvider);
    final TelemetryHistory history = ref.watch(telemetryHistoryProvider);
    final int retentionMinutes = ref.watch(
      appSettingsProvider.select(
        (AppSettings settings) => settings.historyRetentionMinutes,
      ),
    );
    final DashboardLayout layout = ref.watch(dashboardLayoutProvider);

    return AnimatedSwitcher(
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
            retentionLabel: '$retentionMinutes min',
            layout: layout,
          ),
          loading: () => const DashboardSkeleton(),
          error: (Object error, StackTrace stack) => _ErrorState(
            message: error.toString(),
            onRetry: () => ref.read(dashboardSyncProvider).refresh(),
          ),
        ),
      ),
    );
  }
}

/// Fixed, very low-intensity lighting behind the dashboard content. It replaces
/// per-card gradients: the ambient glow reads as depth while the telemetry
/// bodies themselves stay flat and readable.
class _DashboardAmbient extends StatelessWidget {
  const _DashboardAmbient();

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        children: <Widget>[
          Positioned(
            top: -180,
            right: -140,
            child: _glow(520, AuraGlass.ambientBlue),
          ),
          Positioned(
            bottom: -220,
            left: -180,
            child: _glow(560, AuraGlass.ambientViolet),
          ),
        ],
      ),
    );
  }

  Widget _glow(double size, List<Color> colors) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      );
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
    final List<DashboardWidgetConfig> visible = layout.visibleConfigs;
    if (visible.isEmpty) return const _EmptyLayoutState();

    // Use the real content width rather than the screen width: a 1280px window
    // with the desktop sidebar leaves less room than the old hard-coded rule.
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double availableWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : AuraBreakpoints.content.toDouble();
        final int columns = DashboardGrid.columnsFor(availableWidth);
        final List<List<DashboardWidgetConfig>> rows =
            DashboardGrid.groupIntoRows(visible, columns);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            for (int index = 0; index < rows.length; index++) ...<Widget>[
              if (index > 0) const SizedBox(height: DashboardGrid.gap),
              _buildRow(rows[index], columns, availableWidth),
            ],
          ],
        );
      },
    );
  }

  Widget _buildRow(
    List<DashboardWidgetConfig> row,
    int columns,
    double availableWidth,
  ) {
    final List<Widget> children = <Widget>[];
    for (int index = 0; index < row.length; index++) {
      if (index > 0) children.add(const SizedBox(width: DashboardGrid.gap));
      final int span = DashboardGrid.spanFor(row[index], columns);
      // Fixed column-based width: Expanded(flex: span) would stretch a lone
      // compact widget across the whole row.
      children.add(
        SizedBox(
          key: ValueKey<String>('dashboard-card-${row[index].id.name}'),
          width: DashboardGrid.spanWidth(span, availableWidth, columns),
          child: RepaintBoundary(child: _cardFor(row[index].id)),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
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
            'Use the Widget Studio button in the header to show widgets again. '
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
