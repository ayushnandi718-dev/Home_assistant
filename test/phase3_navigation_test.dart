import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/core/services/clock_service.dart';
import 'package:aura_hub/app/shell/aura_sidebar.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardSnapshot> loadDashboard() async {
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
  testWidgets('Phase 3 destinations render from the real app navigation',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dashboardRepositoryProvider
              .overrideWithValue(_FakeDashboardRepository()),
          displayClockProvider.overrideWithValue(
            FixedAuraClock(
              DateTime.utc(2026, 11, 20, 4, 39, 9),
              deviceTimeZoneName: 'IST',
              deviceUtcOffset: Duration(hours: 5, minutes: 30),
            ),
          ),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    // At desktop width the sidebar is expanded: destinations render their
    // labels as text rather than icon tooltips.
    await tester.tap(
      find.descendant(
        of: find.byType(AuraSidebar),
        matching: find.text('Display Studio'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Display Studio'), findsWidgets);
    expect(find.text('Local panel preview'), findsOneWidget);
    expect(find.text('Open widget studio'), findsOneWidget);
    expect(find.textContaining('PLANNED'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(AuraSidebar),
        matching: find.text('Voice & Audio'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Voice & Audio'), findsWidgets);
    expect(find.text('Voice status'), findsOneWidget);
    expect(find.text('Automatic detection — not supported'), findsOneWidget);
    expect(find.textContaining('PLANNED'), findsNothing);

    final Finder firmwareDestination = find.descendant(
      of: find.byType(AuraSidebar),
      matching: find.text('Firmware & Updates'),
    );
    await tester.ensureVisible(firmwareDestination);
    await tester.pumpAndSettle();
    await tester.tap(firmwareDestination);
    await tester.pumpAndSettle();
    expect(find.text('Firmware & Updates'), findsWidgets);
    expect(find.text('Update preferences'), findsOneWidget);
    expect(find.text('No device connected — no update can run'), findsOneWidget);
    expect(find.textContaining('PLANNED'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
