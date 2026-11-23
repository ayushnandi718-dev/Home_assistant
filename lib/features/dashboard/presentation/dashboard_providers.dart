import 'dart:async';

import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/features/dashboard/data/live_dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/telemetry_history.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_sync_controller.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<AuraApiClient> auraApiClientProvider =
    Provider<AuraApiClient>((Ref ref) {
  final AppSettings settings = ref.watch(appSettingsProvider);
  return AuraApiClient(
    baseUrl: settings.apiBaseUrl,
    authToken: ref.watch(telemetryApiAuthTokenProvider),
    onRequest: ref.read(diagnosticsProvider.notifier).record,
    onHealth: (ApiHealth health) {
      ref.read(apiHealthProvider.notifier).record(health);
      ref.read(apiHealthHistoryProvider.notifier).record(health);
      ref.read(diagnosticEventsProvider.notifier).record(
            DiagnosticCategory.apiHealth,
            health.reachable
                ? 'Health check reachable in ${health.responseTime.inMilliseconds} ms.'
                : 'Health check failed: ${health.error ?? 'unknown error'}',
            succeeded: health.reachable,
            error: health.error,
            duration: health.responseTime,
          );
    },
  );
});

final Provider<DashboardRepository> dashboardRepositoryProvider =
    Provider<DashboardRepository>((Ref ref) {
  return LiveDashboardRepository(
    client: ref.watch(auraApiClientProvider),
    onSamplerHealth: ref.read(samplerDiagnosticsProvider.notifier).observe,
  );
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

class TelemetryHistoryNotifier extends StateNotifier<TelemetryHistory> {
  TelemetryHistoryNotifier({int? maxSamples, Duration? retention})
      : super(
          TelemetryHistory(
            maxSamples: maxSamples ?? TelemetryHistory.defaultMaxSamples,
            retention: retention ?? const Duration(minutes: 30),
          ),
        );

  void add(DashboardSnapshot snapshot) =>
      state = state.add(TelemetrySample.fromSnapshot(snapshot));
}

/// Session-only history. It is deliberately not persisted or transmitted.
/// Capacity follows the configured retention and polling interval so a full
/// retention window fits without unbounded growth.
final StateNotifierProvider<TelemetryHistoryNotifier, TelemetryHistory>
    telemetryHistoryProvider =
    StateNotifierProvider<TelemetryHistoryNotifier, TelemetryHistory>(
  (Ref ref) {
    final AppSettings settings = ref.watch(appSettingsProvider);
    final int seconds = settings.pollingIntervalSeconds < 1
        ? 1
        : settings.pollingIntervalSeconds;
    final int capacity =
        (settings.historyRetention.inSeconds ~/ seconds).clamp(60, 1800);
    return TelemetryHistoryNotifier(
      maxSamples: capacity,
      retention: settings.historyRetention,
    );
  },
);

/// Polling controller owned by the dashboard screen.
///
/// This is auto-dispose so leaving the dashboard removes the last listener from
/// [dashboardSnapshotProvider], which disposes the controller and cancels its
/// timer. Returning creates a fresh controller that immediately synchronises.
/// [dashboardStatusProvider] stays alive in the top bar and is the only status
/// source it watches, so it never keeps polling alive by itself.
final AutoDisposeProvider<DashboardSyncController> dashboardSyncProvider =
    Provider.autoDispose<DashboardSyncController>((Ref ref) {
  final StateController<DashboardConnectionStatus> statusNotifier =
      ref.read(dashboardStatusProvider.notifier);
  final DashboardSyncController controller = DashboardSyncController(
    fetch: () => ref.read(dashboardRepositoryProvider).loadDashboard(),
    interval: ref.watch(dashboardPollingIntervalProvider),
    onStatus: (DashboardConnectionStatus status) {
      statusNotifier.state = status;
    },
    onSnapshot: ref.read(telemetryHistoryProvider.notifier).add,
  );
  ref.onDispose(controller.dispose);
  // Riverpod forbids modifying another provider while this one is still
  // building. start() publishes the initial status synchronously, so defer it
  // until construction has completed. controller.dispose() already publishes
  // an idle status on teardown via the onStatus callback.
  scheduleMicrotask(controller.start);
  return controller;
});

/// Keeps the last successful value visible during a refresh, so no loading
/// skeleton flashes every three seconds. Auto-dispose ties the sync lifecycle
/// to dashboard visibility.
final AutoDisposeStreamProvider<DashboardSnapshot> dashboardSnapshotProvider =
    StreamProvider.autoDispose<DashboardSnapshot>((Ref ref) {
  return ref.watch(dashboardSyncProvider).stream;
});
