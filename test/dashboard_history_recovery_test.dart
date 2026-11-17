import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/domain/telemetry_history.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_sync_controller.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/diagnostics/domain/sampler_health.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Repository that can be flipped offline mid-session to exercise recovery.
class FlakyDashboardRepository implements DashboardRepository {
  bool fail = false;
  int _calls = 0;

  @override
  Future<DashboardSnapshot> loadDashboard() async {
    final int call = ++_calls;
    if (fail) throw StateError('local API offline');
    final DateTime now = DateTime.now().add(Duration(seconds: call));
    return DashboardSnapshot(
      devices: const <AuraDevice>[],
      activity: const <ActivityEvent>[],
      coreLink: CoreLinkState.notLinked,
      localApiOnline: true,
      network: NetworkReadiness.configured,
      security: SecurityReadiness.ready,
      generatedAt: now,
      isDemo: false,
      apiUrl: '127.0.0.1:8765',
      samplerHealth: SamplerHealth(
        ready: true,
        healthy: true,
        consecutiveFailures: 0,
        lastSuccessAt: now,
      ),
      system: SystemMetrics(
        hostName: 'TEST-PC',
        osName: 'Windows',
        bootTime: DateTime(2026, 1, 1),
        uptimeSeconds: 3600,
        cpuPercent: call.toDouble(),
        cpuCores: 4,
        cpuFrequencyMHz: 2400,
        perCoreCpu: const <double>[10, 10, 10, 10],
        memoryTotalBytes: 8 * 1024 * 1024 * 1024,
        memoryUsedBytes: 4 * 1024 * 1024 * 1024,
        memoryAvailableBytes: 4 * 1024 * 1024 * 1024,
        memoryPercent: 50,
        diskPath: 'C:\\',
        diskTotalBytes: 100 * 1024 * 1024 * 1024,
        diskUsedBytes: 60 * 1024 * 1024 * 1024,
        diskFreeBytes: 40 * 1024 * 1024 * 1024,
        diskPercent: 60,
        bytesSent: 1000,
        bytesReceived: 2000,
        sentPerSecond: 100,
        receivedPerSecond: 200,
        activeInterfaceCount: 1,
        processCount: 100,
        topProcesses: const <TopProcess>[],
        batteryPercent: 80,
        batteryPlugged: true,
        batterySecondsLeft: null,
        firewallEnabled: true,
        firewallState: FirewallReadiness.enabled,
      ),
    );
  }
}

void main() {
  test('history records only healthy samples across offline recovery',
      () async {
    final ProviderContainer container = ProviderContainer();
    addTearDown(container.dispose);
    final FlakyDashboardRepository repository = FlakyDashboardRepository();
    final List<DashboardSnapshot> emitted = <DashboardSnapshot>[];

    final DashboardSyncController controller = DashboardSyncController(
      fetch: repository.loadDashboard,
      interval: const Duration(hours: 1),
      onSnapshot: container.read(telemetryHistoryProvider.notifier).add,
    );
    addTearDown(controller.dispose);
    controller.stream.listen(emitted.add);

    // The controller uses a broadcast stream, so stream data is delivered in a
    // later microtask. Flush it before asserting on emitted snapshots.
    Future<void> poll() async {
      await controller.refresh();
      await Future<void>.delayed(Duration.zero);
    }

    // 1. Healthy poll: a real sample is recorded and the stream is live.
    await poll();
    expect(emitted, hasLength(1));
    expect(emitted.last.stale, isFalse);
    expect(container.read(telemetryHistoryProvider).length, 1);
    final TelemetrySample first =
        container.read(telemetryHistoryProvider).samples.single;
    expect(first.cpuPercent, 1);
    expect(first.memoryPercent, isNotNull,
        reason: 'a healthy sampler reading must not become a zero/null gap');

    // 2. Offline poll: the stale snapshot is emitted but never recorded.
    repository.fail = true;
    await poll();
    expect(emitted, hasLength(2));
    expect(emitted.last.stale, isTrue);
    expect(emitted.last.localApiOnline, isFalse);
    expect(container.read(telemetryHistoryProvider).length, 1,
        reason: 'failed/stale samples must never enter the trend history');

    // 3. Reconnect: only the new successful sample is appended.
    repository.fail = false;
    await poll();
    expect(emitted, hasLength(3));
    expect(emitted.last.stale, isFalse);
    expect(emitted.last.localApiOnline, isTrue);
    final TelemetryHistory history = container.read(telemetryHistoryProvider);
    expect(history.length, 2);
    expect(
      history.samples.map((TelemetrySample s) => s.cpuPercent).toList(),
      <double?>[1, 3],
      reason: 'the stale sample is skipped, so the second sample is poll #3',
    );
  });
}
