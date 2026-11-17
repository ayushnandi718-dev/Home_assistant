import 'dart:async';

import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/features/dashboard/data/live_dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<AuraApiClient> auraApiClientProvider =
    Provider<AuraApiClient>((Ref ref) {
  final AppSettings settings = ref.watch(appSettingsProvider);
  return AuraApiClient(
    baseUrl: settings.apiBaseUrl,
    onRequest: ref.read(diagnosticsProvider.notifier).record,
  );
});

final Provider<DashboardRepository> dashboardRepositoryProvider =
    Provider<DashboardRepository>((Ref ref) {
  return LiveDashboardRepository(client: ref.watch(auraApiClientProvider));
});

/// Poll interval for Windows host telemetry, sourced from persisted settings.
final Provider<Duration> dashboardPollingIntervalProvider =
    Provider<Duration>((Ref ref) {
  return ref.watch(appSettingsProvider).pollingInterval;
});

/// Lightweight connection state. The top bar watches this instead of the
/// telemetry stream, so leaving the dashboard actually stops polling.
final StateProvider<DashboardConnectionStatus> dashboardStatusProvider =
    StateProvider<DashboardConnectionStatus>((Ref ref) {
  return const DashboardConnectionStatus();
});

/// Single polling controller for the whole app lifecycle. Disposing this
/// provider cancels the timer and closes the broadcast stream.
final Provider<DashboardSyncController> dashboardSyncProvider =
    Provider<DashboardSyncController>((Ref ref) {
  final StateController<DashboardConnectionStatus> statusNotifier =
      ref.read(dashboardStatusProvider.notifier);
  final DashboardSyncController controller = DashboardSyncController(
    fetch: () => ref.read(dashboardRepositoryProvider).loadDashboard(),
    interval: ref.watch(dashboardPollingIntervalProvider),
    onStatus: (DashboardConnectionStatus status) {
      statusNotifier.state = status;
    },
  );
  ref.onDispose(controller.dispose);
  // Riverpod forbids modifying another provider while this one is still
  // building. start() publishes the initial status synchronously, so defer it
  // until construction has completed. controller.dispose() already publishes
  // an idle status on teardown via the onStatus callback.
  scheduleMicrotask(controller.start);
  return controller;
});

/// StreamProvider keeps the last successful value visible during a refresh,
/// so no loading skeleton flashes every three seconds.
final StreamProvider<DashboardSnapshot> dashboardSnapshotProvider =
    StreamProvider<DashboardSnapshot>((Ref ref) {
  return ref.watch(dashboardSyncProvider).stream;
});
