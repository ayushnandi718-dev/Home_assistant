import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/app/navigation.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/api_startup_guide.dart';
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

class FailingDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardSnapshot> loadDashboard() async {
    throw StateError('offline test host');
  }
}

DashboardLayout _singleCompactLayout() => DashboardLayout(
      <DashboardWidgetConfig>[
        const DashboardWidgetConfig(
          id: DashboardWidgetId.quickActions,
          visible: true,
          size: DashboardWidgetSize.compact,
        ),
      ],
    );

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
    expect(find.text('HTTP API'), findsOneWidget);
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

  testWidgets('mobile Home is a device control center, not host telemetry',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
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

    // SmartThings-style tile hierarchy: weather/time, panel/devices, scenes,
    // glanceable facts, then real device activity.
    expect(find.byKey(const ValueKey<String>('weather-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('time-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('panel-tile')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('devices-tile')), findsOneWidget);
    expect(find.text('Weather'), findsOneWidget);
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
    expect(find.text('Recent activity'), findsOneWidget);

    // Quick controls and the live preview belong outside this dashboard.
    expect(find.text('Quick controls'), findsNothing);
    expect(find.text('Live panel preview'), findsNothing);
    expect(find.text('Local preview'), findsNothing);

    // Windows host telemetry belongs on Diagnostics, never on mobile Home.
    expect(find.text('HOST CPU'), findsNothing);
    expect(find.text('HOST MEMORY'), findsNothing);
    expect(find.text('Source health'), findsNothing);
    expect(find.text('Telemetry sampler'), findsNothing);
    expect(find.text('Recent Windows host events'), findsNothing);
    expect(find.text('LOCAL TELEMETRY API'), findsNothing);
    expect(find.text('HTTP API'), findsNothing);
    expect(find.textContaining('local API at'), findsNothing);
    expect(find.textContaining('API healthy'), findsNothing);
    expect(
        find.textContaining('Local telemetry API unavailable'), findsNothing);
    expect(find.byType(ApiStartupGuide), findsNothing);
    expect(find.byTooltip('Diagnostics issue'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile panel tile routes to Devices',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
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

    await tester.tap(find.byKey(const ValueKey<String>('panel-tile')));
    await tester.pumpAndSettle();

    expect(find.text('Connection status'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile issue indicator opens Diagnostics',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final DiagnosticEventsNotifier events = DiagnosticEventsNotifier()
      ..record(
        DiagnosticCategory.devicePairing,
        'Pairing failed in test.',
        succeeded: false,
      );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dashboardRepositoryProvider
              .overrideWithValue(FakeDashboardRepository()),
          diagnosticEventsProvider.overrideWith((Ref ref) => events),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Diagnostics issue'), findsOneWidget);
    await tester.tap(find.byTooltip('Diagnostics issue'));
    await tester.pumpAndSettle();

    expect(find.text('Diagnostics'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mobile Home does not surface host dashboard load errors',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider
              .overrideWithValue(FailingDashboardRepository()),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Could not load dashboard data'), findsNothing);
    expect(find.byKey(const ValueKey<String>('panel-tile')), findsOneWidget);
    expect(find.byType(ApiStartupGuide), findsNothing);
    expect(find.text('Restart service'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('dashboard scroll path avoids expensive per-frame work',
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

    final Finder scrollArea = find.byType(AuraScrollArea);
    expect(scrollArea, findsOneWidget);
    expect(find.byType(IntrinsicHeight), findsNothing);
    expect(
      find.descendant(
        of: scrollArea,
        matching: find.byWidgetPredicate(
          (Widget widget) => widget is GridView && widget.shrinkWrap,
        ),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: scrollArea,
        matching: find.byWidgetPredicate(
          (Widget widget) => widget is BackdropFilter,
        ),
      ),
      findsNothing,
      reason: 'Content inside the scroll view must not sample the backdrop',
    );

    await tester.drag(scrollArea, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
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

  testWidgets('one compact widget stays one column wide on desktop',
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
              .overrideWithValue(FakeDashboardRepository()),
          dashboardLayoutProvider.overrideWithValue(_singleCompactLayout()),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    final Finder card =
        find.byKey(const ValueKey<String>('dashboard-card-quickActions'));
    expect(card, findsOneWidget);
    final double width = tester.getSize(card).width;
    expect(width, greaterThan(200));
    expect(width, lessThan(1440 * 0.4), reason: 'one column, not the full row');
    expect(tester.takeException(), isNull);
  });

  testWidgets('one compact widget stays one column wide on tablet',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(900, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          dashboardRepositoryProvider
              .overrideWithValue(FakeDashboardRepository()),
          dashboardLayoutProvider.overrideWithValue(_singleCompactLayout()),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    final Finder card =
        find.byKey(const ValueKey<String>('dashboard-card-quickActions'));
    expect(card, findsOneWidget);
    final double width = tester.getSize(card).width;
    expect(width, greaterThan(200));
    expect(width, lessThan(900 * 0.55), reason: 'one column, not the full row');
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI Assistant route renders the real chat workspace',
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

    await tester.tap(find.text('AI Assistant').first);
    await tester.pumpAndSettle();

    expect(find.text('AURA Assistant'), findsOneWidget);
    expect(find.text('Where should we begin?'), findsOneWidget);
    expect(find.text('External AI requests are off'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
