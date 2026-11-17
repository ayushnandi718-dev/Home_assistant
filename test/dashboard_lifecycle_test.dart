import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Counts fetches so the test can prove polling actually stops and restarts.
class CountingDashboardRepository implements DashboardRepository {
  int calls = 0;

  @override
  Future<DashboardSnapshot> loadDashboard() async {
    calls++;
    final DateTime now = DateTime.now();
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
      system: SystemMetrics(
        hostName: 'TEST-PC',
        osName: 'Windows',
        bootTime: now,
        uptimeSeconds: 3600,
        cpuPercent: 10,
        cpuCores: 4,
        cpuFrequencyMHz: 2400,
        perCoreCpu: const <double>[10, 10, 10, 10],
        memoryTotalBytes: 8 * 1024 * 1024 * 1024,
        memoryUsedBytes: 4 * 1024 * 1024 * 1024,
        memoryAvailableBytes: 4 * 1024 * 1024 * 1024,
        memoryPercent: 50,
        diskPath: 'C:\\',
        diskTotalBytes: 100 * 1024 * 1024 * 1024,
        diskUsedBytes: 40 * 1024 * 1024 * 1024,
        diskFreeBytes: 60 * 1024 * 1024 * 1024,
        diskPercent: 40,
        bytesSent: 1000,
        bytesReceived: 2000,
        sentPerSecond: 10,
        receivedPerSecond: 20,
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('leaving the dashboard stops polling; returning restarts it',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final CountingDashboardRepository repository =
        CountingDashboardRepository();
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        dashboardRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(repository.calls, 1, reason: 'initial immediate synchronisation');
    expect(container.read(dashboardStatusProvider).active, isTrue);

    // Leave the dashboard.
    await tester.tap(find.text('Devices').first);
    await tester.pumpAndSettle();

    expect(container.read(dashboardStatusProvider).active, isFalse,
        reason: 'top bar reports idle once polling is torn down');
    final int callsAfterLeaving = repository.calls;
    await tester.pump(const Duration(seconds: 9));
    expect(repository.calls, callsAfterLeaving,
        reason: 'no polling continues while the dashboard is inactive');

    // Return to the dashboard: a fresh controller syncs immediately.
    await tester.tap(find.text('Dashboard').first);
    await tester.pumpAndSettle();

    expect(repository.calls, callsAfterLeaving + 1,
        reason: 'returning starts one fresh immediate synchronisation');
    expect(container.read(dashboardStatusProvider).active, isTrue);

    await tester.pump(const Duration(seconds: 3));
    expect(repository.calls, callsAfterLeaving + 2,
        reason: 'polling resumes at the configured interval');
  });
}
