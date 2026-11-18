import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/app/navigation.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardSnapshot> loadDashboard() async {
    final DateTime now = DateTime.now();
    return DashboardSnapshot(
      devices: const <AuraDevice>[],
      activity: <ActivityEvent>[
        ActivityEvent(
          id: 'test-event',
          title: 'Host CPU 10.0%',
          detail: 'Sampled from the test Windows host.',
          category: ActivityCategory.system,
          severity: ActivitySeverity.info,
          timestamp: now,
          isDemo: false,
        ),
      ],
      coreLink: CoreLinkState.notLinked,
      localApiOnline: true,
      network: NetworkReadiness.configured,
      security: SecurityReadiness.ready,
      generatedAt: now,
      isDemo: false,
      apiUrl: '127.0.0.1:8765',
      system: SystemMetrics(
        hostName: 'TEST-HOST',
        osName: 'Windows test build',
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

  testWidgets('dashboard separates host telemetry from AURA device status',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider
              .overrideWithValue(FakeDashboardRepository()),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    // The source banner states the API is healthy AND that no device is paired.
    expect(find.text('API healthy · no AURA device paired'), findsOneWidget);
    expect(find.text('HOST CPU'), findsOneWidget);
    expect(find.text('LOCAL TELEMETRY API'), findsOneWidget);
    expect(find.text('Online'), findsAtLeastNWidgets(1));
    expect(find.text('AURA CORE'), findsOneWidget);
    expect(find.text('Not linked'), findsOneWidget);
    expect(find.text('No AURA devices connected'), findsOneWidget);
    expect(find.text('Recent Windows host events'), findsOneWidget);

    await tester.tap(find.text('Devices').first);
    await tester.pumpAndSettle();

    expect(find.text('Connection status'), findsOneWidget);
    expect(
      find.textContaining('never represents a paired device'),
      findsOneWidget,
    );
  });

  testWidgets(
      'compact desktop width renders every destination without overflow',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(860, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider
              .overrideWithValue(FakeDashboardRepository()),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    // A compact sidebar shows icons with tooltips rather than full labels.
    for (final AuraDestination destination in auraDestinations) {
      expect(find.byTooltip(destination.label), findsWidgets,
          reason: 'Missing nav tile for ${destination.path}');
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile width uses bottom navigation and more sheet',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(460, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider
              .overrideWithValue(FakeDashboardRepository()),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Profiles & Security'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
