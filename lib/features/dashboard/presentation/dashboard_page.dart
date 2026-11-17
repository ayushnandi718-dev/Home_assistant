import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/activity_feed_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/dashboard_skeleton.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/device_spotlight_card.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/greeting_header.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/live_data_notice.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/overview_grid.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/quick_actions_card.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
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
                onRefresh: () => ref.invalidate(dashboardSnapshotProvider),
              ),
              const SizedBox(height: AuraSpace.lg),
              LiveDataNotice(apiUrl: apiUrl, generatedAt: sampledAt),
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
                    data: (DashboardSnapshot snapshot) =>
                        _DashboardBody(snapshot: snapshot),
                    loading: () => const DashboardSkeleton(),
                    error: (Object error, StackTrace stack) => _ErrorState(
                      message: error.toString(),
                      onRetry: () => ref.invalidate(dashboardSnapshotProvider),
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
  const _DashboardBody({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final bool wide = MediaQuery.sizeOf(context).width >= 1180;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        OverviewGrid(snapshot: snapshot),
        const SizedBox(height: AuraSpace.lg),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final Widget device =
                DeviceSpotlightCard(devices: snapshot.devices);
            const Widget actions = QuickActionsCard();
            if (wide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 3, child: device),
                  const SizedBox(width: AuraSpace.lg),
                  const Expanded(flex: 2, child: actions),
                ],
              );
            }
            return Column(
              children: <Widget>[
                device,
                const SizedBox(height: AuraSpace.lg),
                actions,
              ],
            );
          },
        ),
        const SizedBox(height: AuraSpace.lg),
        ActivityFeedCard(events: snapshot.activity),
      ],
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
