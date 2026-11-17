import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/domain/telemetry_history.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/diagnostics/domain/sampler_health.dart';
import 'package:flutter_test/flutter_test.dart';

DashboardSnapshot _snapshot({
  required DateTime at,
  double cpu = 20,
  double memory = 40,
  double disk = 60,
  double sent = 100,
  double received = 200,
  SamplerHealth? sampler,
  bool stale = false,
}) {
  return DashboardSnapshot(
    devices: const <AuraDevice>[],
    activity: const <ActivityEvent>[],
    coreLink: CoreLinkState.notLinked,
    localApiOnline: !stale,
    stale: stale,
    network: NetworkReadiness.configured,
    security: SecurityReadiness.ready,
    generatedAt: at,
    isDemo: false,
    apiUrl: '127.0.0.1:8765',
    samplerHealth: sampler ??
        SamplerHealth(
          ready: true,
          healthy: true,
          consecutiveFailures: 0,
          lastSuccessAt: at,
        ),
    system: SystemMetrics(
      hostName: 'TEST-PC',
      osName: 'Windows',
      bootTime: at,
      uptimeSeconds: 3600,
      cpuPercent: cpu,
      cpuCores: 4,
      cpuFrequencyMHz: 2400,
      perCoreCpu: const <double>[10, 10, 10, 10],
      memoryTotalBytes: 8 * 1024 * 1024 * 1024,
      memoryUsedBytes: 4 * 1024 * 1024 * 1024,
      memoryAvailableBytes: 4 * 1024 * 1024 * 1024,
      memoryPercent: memory,
      diskPath: 'C:\\',
      diskTotalBytes: 100 * 1024 * 1024 * 1024,
      diskUsedBytes: 60 * 1024 * 1024 * 1024,
      diskFreeBytes: 40 * 1024 * 1024 * 1024,
      diskPercent: disk,
      bytesSent: 1000,
      bytesReceived: 2000,
      sentPerSecond: sent,
      receivedPerSecond: received,
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

final DateTime _base = DateTime(2026, 1, 1);

TelemetrySample _sample(int secondsFromBase) => TelemetrySample(
      timestamp: _base.add(Duration(seconds: secondsFromBase)),
      cpuPercent: secondsFromBase.toDouble(),
    );

void main() {
  test('circular buffer stops at capacity and stays ordered after wrapping',
      () {
    TelemetryHistory history =
        const TelemetryHistory(maxSamples: 3, retention: Duration(hours: 1));
    for (int second = 1; second <= 5; second++) {
      history = history.add(_sample(second));
    }

    expect(history.length, 3);
    expect(history.maxSamples, 3);
    expect(
      history.samples.map((TelemetrySample s) => s.timestamp.second).toList(),
      <int>[3, 4, 5],
      reason: 'oldest sample is overwritten and chronological order is kept',
    );
    final int revision = history.revision;
    expect(revision, 5);
  });

  test('retention drops samples older than the configured window', () {
    TelemetryHistory history = TelemetryHistory(
      maxSamples: 10,
      retention: const Duration(minutes: 1),
    );
    history = history.add(_sample(0));
    history = history.add(_sample(30));
    history = history.add(_sample(90));

    expect(history.length, 2);
    expect(
      history.samples
          .map((TelemetrySample s) => s.timestamp.difference(_base).inSeconds)
          .toList(),
      <int>[30, 90],
    );
  });

  test('missing or unhealthy measurements are gaps, never zero readings', () {
    final DateTime at = DateTime(2026, 1, 1, 12);
    final TelemetrySample healthy = TelemetrySample.fromSnapshot(
      _snapshot(at: at, cpu: 25, sent: 100, received: 200),
    );
    expect(healthy.cpuPercent, 25);
    expect(healthy.bytesSentPerSecond, 100);
    expect(healthy.bytesReceivedPerSecond, 200);

    final TelemetrySample degraded = TelemetrySample.fromSnapshot(
      _snapshot(
        at: at,
        cpu: double.nan,
        sent: double.nan,
        sampler: SamplerHealth(
          ready: true,
          healthy: false,
          consecutiveFailures: 1,
          lastError: 'OSError',
        ),
      ),
    );
    expect(degraded.cpuPercent, isNull);
    expect(degraded.bytesSentPerSecond, isNull);
    expect(degraded.bytesReceivedPerSecond, isNull);

    final TelemetrySample stale = TelemetrySample.fromSnapshot(
      _snapshot(at: at, stale: true),
    );
    expect(stale.cpuPercent, isNull);
    expect(stale.memoryPercent, isNull);
  });
}
