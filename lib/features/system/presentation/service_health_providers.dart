import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/lifecycle/background_service.dart';
import 'package:aura_hub/core/lifecycle/service_health_monitor.dart';
import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/notifications/domain/aura_notification.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Aggregates app-wide service health and raises notifications only on real
/// state transitions. First checks do not spam the centre when everything is
/// healthy.
class ServiceHealthController extends StateNotifier<ApiHealth?> {
  ServiceHealthController(this._ref) : super(null);

  final Ref _ref;

  void observe(ApiHealth health) {
    final ApiHealth? previous = state;
    state = health;

    _ref.read(auraLoggerProvider.notifier).log(
      health.reachable && health.samplerHealthy
          ? AuraLogLevel.info
          : AuraLogLevel.warning,
      'service-health',
      health.reachable
          ? 'API reachable, sampler ${health.samplerLabel.toLowerCase()}.'
          : 'API unreachable: ${health.error ?? 'unknown error'}',
      context: <String, String>{
        'responseTimeMs': '${health.responseTime.inMilliseconds}',
      },
    );
    _publishTransitions(previous, health);
  }

  void _publishTransitions(ApiHealth? previous, ApiHealth current) {
    final NotificationCenter center =
        _ref.read(activeNotificationCenterProvider);

    if (previous == null) {
      if (!current.reachable) {
        center.publish(
          id: 'api-availability',
          title: 'Telemetry API offline',
          body: current.error ?? 'The local AURA API could not be reached.',
          severity: NotificationSeverity.error,
          source: NotificationSource.api,
        );
      }
      return;
    }

    if (previous.reachable != current.reachable) {
      center.publish(
        id: 'api-availability',
        title: current.reachable
            ? 'Telemetry API online'
            : 'Telemetry API offline',
        body: current.reachable
            ? 'Local API responded in ${current.responseTime.inMilliseconds} ms.'
            : (current.error ?? 'The local AURA API could not be reached.'),
        severity: current.reachable
            ? NotificationSeverity.success
            : NotificationSeverity.error,
        source: NotificationSource.api,
      );
    }

    // Sampler health is not observable while the API is unreachable. Only
    // report a sampler transition when both checks could actually see it.
    if (current.reachable &&
        previous.reachable &&
        previous.samplerHealthy != current.samplerHealthy) {
      center.publish(
        id: 'sampler-health',
        title: current.samplerHealthy ? 'Sampler healthy' : 'Sampler degraded',
        body: current.samplerHealthy
            ? 'Background telemetry sampling recovered.'
            : (current.samplerLastError ?? 'Sampling reported a failure.'),
        severity: current.samplerHealthy
            ? NotificationSeverity.success
            : NotificationSeverity.warning,
        source: NotificationSource.sampler,
      );
    }
  }
}

final StateNotifierProvider<ServiceHealthController, ApiHealth?>
    serviceHealthProvider =
    StateNotifierProvider<ServiceHealthController, ApiHealth?>(
  (Ref ref) => ServiceHealthController(ref),
);

/// In-process monitor. It never starts, stops or spawns the Python API.
final Provider<ServiceHealthMonitor> serviceHealthMonitorProvider =
    Provider<ServiceHealthMonitor>((Ref ref) {
  final AuraApiClient client = ref.read(auraApiClientProvider);
  return ServiceHealthMonitor(
    interval: AuraRuntimeConfig.serviceHealthInterval,
    probe: () async {
      try {
        return await client.checkHealth();
      } on AuraApiException catch (error) {
        // checkHealth already publishes the failure through its callbacks;
        // return an equivalent value so the monitor can update its state too.
        return ApiHealth.failure(
          checkedAt: DateTime.now(),
          responseTime: Duration.zero,
          error: error.message,
        );
      }
    },
    onResult: (ApiHealth health) =>
        ref.read(serviceHealthProvider.notifier).observe(health),
  );
});

/// Registers all in-process background services with one lifecycle owner.
final Provider<ServiceLifecycleManager> serviceLifecycleProvider =
    Provider<ServiceLifecycleManager>((Ref ref) {
  final ServiceLifecycleManager manager = ServiceLifecycleManager();
  manager.register(ref.read(serviceHealthMonitorProvider));
  ref.onDispose(manager.stopAll);
  return manager;
});
