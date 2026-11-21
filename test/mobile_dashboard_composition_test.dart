import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

/// Host telemetry fixture used only to prove the desktop branch is preserved.
/// The mobile branch must never build any widget from this snapshot.
class _DesktopTelemetryRepository implements DashboardRepository {
  @override
  Future<DashboardSnapshot> loadDashboard() async {
    final DateTime now = DateTime.now();
    return DashboardSnapshot(
      devices: const <AuraDevice>[],
      activity: <ActivityEvent>[
        ActivityEvent(
          id: 'composition-test-event',
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

Future<void> _pumpApp(
  WidgetTester tester, {
  required Size size,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dashboardRepositoryProvider
            .overrideWithValue(_DesktopTelemetryRepository()),
        ...overrides,
      ],
      child: const AuraApp(),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('476px builds the mobile device-control dashboard only',
      (WidgetTester tester) async {
    final DiagnosticEventsNotifier events = DiagnosticEventsNotifier()
      ..record(
        DiagnosticCategory.telemetry,
        'Host telemetry failed in composition test.',
        succeeded: false,
      );

    await _pumpApp(
      tester,
      size: const Size(476, 900),
      overrides: <Override>[
        diagnosticEventsProvider.overrideWith((Ref ref) => events),
      ],
    );

    expect(
        find.byKey(const ValueKey<String>('mobile-dashboard')), findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('desktop-dashboard')), findsNothing);

    expect(find.byKey(const ValueKey<String>('weather-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('time-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('panel-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('devices-tile')), findsOneWidget);
    expect(find.text('AURA panel'), findsOneWidget);
    expect(find.text('Not paired'), findsWidgets);
    expect(find.text('Connected devices'), findsOneWidget);
    expect(find.text('Night mode'), findsOneWidget);
    expect(find.text('Next wallpaper'), findsOneWidget);
    expect(find.text('Sync now'), findsOneWidget);
    expect(find.text('Restart panel'), findsOneWidget);
    expect(find.text('Phone Wi-Fi'), findsOneWidget);
    expect(find.text('Phone battery'), findsOneWidget);
    expect(find.text('Panel Wi-Fi'), findsOneWidget);
    expect(find.text('Panel last seen'), findsOneWidget);
    expect(find.text('Recent activity'), findsOneWidget);

    // All four scene pills are inert until a real panel reports connected.
    for (final String action in <String>[
      'nightMode',
      'nextWallpaper',
      'syncNow',
      'restartPanel',
    ]) {
      final Finder pill = find.byKey(ValueKey<String>('scene-pill-$action'));
      expect(pill, findsOneWidget);
      expect(
        tester
            .widget<InkWell>(
              find.descendant(of: pill, matching: find.byType(InkWell)),
            )
            .onTap,
        isNull,
        reason: '$action must not run without a paired panel',
      );
    }

    expect(find.text('Live panel preview'), findsNothing);
    expect(find.text('Quick controls'), findsNothing);
    expect(find.text('Open Display Studio'), findsNothing);

    // No Windows host telemetry card may be built on mobile.
    expect(find.text('Host data unavailable'), findsNothing);
    expect(find.text('Source health'), findsNothing);
    expect(find.text('HOST CPU'), findsNothing);
    expect(find.text('HOST MEMORY'), findsNothing);
    expect(find.text('Telemetry sampler'), findsNothing);
    expect(find.text('LOCAL TELEMETRY API'), findsNothing);
    expect(find.text('Recent Windows host events'), findsNothing);
    expect(
        find.text('Host telemetry failed in composition test.'), findsNothing);

    // The single issue indicator is device-relevant; host telemetry failures
    // are expected on Android and must not light it.
    expect(find.byTooltip('Diagnostics issue'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile recent activity excludes host diagnostics',
      (WidgetTester tester) async {
    final DiagnosticEventsNotifier events = DiagnosticEventsNotifier()
      ..record(
        DiagnosticCategory.telemetry,
        'Host telemetry should stay in Diagnostics.',
      )
      ..record(
        DiagnosticCategory.devicePairing,
        'Pairing requested in composition test.',
      );

    await _pumpApp(
      tester,
      size: const Size(393, 873),
      overrides: <Override>[
        diagnosticEventsProvider.overrideWith((Ref ref) => events),
      ],
    );

    expect(find.text('Pairing requested in composition test.'), findsOneWidget);
    expect(
        find.text('Host telemetry should stay in Diagnostics.'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop keeps the Windows telemetry composition',
      (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(1280, 900));

    expect(find.byKey(const ValueKey<String>('desktop-dashboard')),
        findsOneWidget);
    expect(
        find.byKey(const ValueKey<String>('mobile-dashboard')), findsNothing);

    expect(find.text('Source health'), findsOneWidget);
    expect(find.text('HOST CPU'), findsOneWidget);
    expect(find.text('LOCAL TELEMETRY API'), findsOneWidget);
    expect(find.text('Recent Windows host events'), findsOneWidget);

    expect(find.byKey(const ValueKey<String>('panel-tile')), findsNothing);
    expect(find.text('Live panel preview'), findsNothing);
    expect(find.text('Quick controls'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('476px content scrolls clear of the floating capsule',
      (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(476, 900));

    final Finder scrollArea = find.byType(AuraScrollArea);
    expect(scrollArea, findsOneWidget);
    final SingleChildScrollView view = tester.widget<SingleChildScrollView>(
      find.descendant(
          of: scrollArea, matching: find.byType(SingleChildScrollView)),
    );
    expect((view.padding! as EdgeInsets).bottom, greaterThanOrEqualTo(120));

    expect(find.byType(FBottomNavigationBar), findsOneWidget);

    await tester.drag(
      find.descendant(
          of: scrollArea, matching: find.byType(SingleChildScrollView)),
      const Offset(0, -4000),
    );
    await tester.pumpAndSettle();

    final Finder recentCard = find.ancestor(
      of: find.text('Recent activity'),
      matching: find.byType(SurfaceCard),
    );
    final double cardBottom = tester.getBottomRight(recentCard.first).dy;
    final double navTop =
        tester.getTopLeft(find.byType(FBottomNavigationBar)).dy;
    expect(cardBottom, lessThan(navTop));
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile header keeps the active workspace isolated',
      (WidgetTester tester) async {
    await _pumpApp(tester, size: const Size(476, 900));

    // The app always starts in the shared, unauthenticated FAMILY workspace.
    expect(find.textContaining('FAMILY workspace'), findsWidgets);
    expect(find.byTooltip('Workspace'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
