import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/app/shell/app_top_bar.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:flutter_test/flutter_test.dart';

/// Local, explicitly non-demo snapshot. It keeps widget tests offline while
/// never presenting fake device telemetry as real hardware.
class _OfflineTestDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardSnapshot> loadDashboard() async {
    final DateTime now = DateTime.now();
    return DashboardSnapshot(
      devices: const <AuraDevice>[],
      activity: const <ActivityEvent>[],
      coreLink: CoreLinkState.notLinked,
      localApiOnline: false,
      network: NetworkReadiness.configured,
      security: SecurityReadiness.ready,
      generatedAt: now,
      isDemo: false,
      apiUrl: '127.0.0.1:8765',
      system: SystemMetrics(
        hostName: 'TEST-HOST',
        osName: 'Flutter widget test',
        bootTime: now,
        uptimeSeconds: 0,
        cpuPercent: 0,
        cpuCores: 1,
        cpuFrequencyMHz: 0,
        perCoreCpu: const <double>[0],
        memoryTotalBytes: 0,
        memoryUsedBytes: 0,
        memoryAvailableBytes: 0,
        memoryPercent: 0,
        diskPath: 'C:\\',
        diskTotalBytes: 0,
        diskUsedBytes: 0,
        diskFreeBytes: 0,
        diskPercent: 0,
        bytesSent: 0,
        bytesReceived: 0,
        sentPerSecond: 0,
        receivedPerSecond: 0,
        activeInterfaceCount: 0,
        processCount: 0,
        topProcesses: const <TopProcess>[],
        batteryPercent: null,
        batteryPlugged: false,
        batterySecondsLeft: null,
        firewallEnabled: false,
        firewallState: FirewallReadiness.unavailable,
      ),
    );
  }
}

final List<Size> _phoneSizes = <Size>[
  Size(360, 800),
  // Samsung F15: 1080x2340 @ 450dpi => 384x832 logical pixels.
  Size(384, 832),
  Size(393, 873),
  Size(460, 900),
];

void _configureView(
  WidgetTester tester,
  Size size, {
  double statusBar = 0,
  double gestureInset = 0,
}) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(
    top: statusBar,
    bottom: gestureInset,
  );
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
  });
}

/// `TestFlutterView.viewInsets` does not feed MediaQuery in this Flutter
/// build, so the keyboard is simulated by overriding MediaQuery directly.
/// This is the same data Android's `adjustResize` delivers to Flutter.
Future<void> _pumpShell(
  WidgetTester tester, {
  double keyboard = 0,
}) async {
  final MediaQueryData base = MediaQueryData.fromView(tester.view);
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dashboardRepositoryProvider
            .overrideWithValue(_OfflineTestDashboardRepository()),
      ],
      child: MediaQuery(
        data: base.copyWith(
          viewInsets: EdgeInsets.only(bottom: keyboard),
        ),
        child: const AuraApp(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Some destination previews intentionally animate forever. A bounded pump
/// finishes route/sheet transitions without waiting for those decorative
/// animations to stop.
Future<void> _pumpNavigation(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump();
}

Future<void> _openAiAssistant(WidgetTester tester) async {
  await _openMoreDestination(tester, 'AI Assistant');
  expect(find.text('AURA Assistant'), findsWidgets);
}

Future<void> _openMoreDestination(WidgetTester tester, String label) async {
  await tester.tap(find.text('More'));
  await _pumpNavigation(tester);
  final Finder destination = find.text(label).last;
  await tester.ensureVisible(destination);
  await _pumpNavigation(tester);
  await tester.tap(destination);
  await _pumpNavigation(tester);
}

Future<void> _openPrimaryDestination(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(
      of: find.byType(FBottomNavigationBar),
      matching: find.text(label),
    ),
  );
  await _pumpNavigation(tester);
}

Future<void> _openSettings(WidgetTester tester) async {
  await _openMoreDestination(tester, 'Settings');
  expect(find.text('Display density'), findsOneWidget);
}

Finder _composerFinder() => find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField &&
          (widget.decoration?.hintText ?? '').contains('Ask AURA anything'),
    );

void main() {
  for (final Size size in _phoneSizes) {
    testWidgets(
      'Dashboard header clears the Android status bar at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (WidgetTester tester) async {
        _configureView(tester, size, statusBar: 32);
        await _pumpShell(tester);

        expect(find.byType(AppTopBar), findsOneWidget);
        final Rect topBar = tester.getRect(find.byType(AppTopBar));
        expect(
          topBar.top,
          greaterThanOrEqualTo(32),
          reason: 'Top bar rendered underneath the status bar',
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Settings labels keep a readable width at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (WidgetTester tester) async {
        _configureView(tester, size, statusBar: 32);
        await _pumpShell(tester);
        await _openSettings(tester);

        final Finder title = find.text('Display density');
        final Finder subtitle = find.text('Spacing and control sizing.');
        expect(title, findsOneWidget);
        expect(subtitle, findsOneWidget);
        expect(
          tester.getRect(title).width,
          greaterThan(140),
          reason: 'Settings text was squeezed into a near-zero width column',
        );
        expect(
          tester.getRect(subtitle).width,
          greaterThan(140),
          reason: 'Settings subtitle wrapped one character per line',
        );
        expect(find.text('Comfortable'), findsOneWidget);
        expect(find.text('Compact'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'AI composer stays above the keyboard at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (WidgetTester tester) async {
        _configureView(tester, size);
        await _pumpShell(tester, keyboard: 300);
        await _openAiAssistant(tester);

        expect(_composerFinder(), findsOneWidget);
        final Rect composer = tester.getRect(_composerFinder());
        expect(
          composer.bottom,
          lessThanOrEqualTo(size.height - 300 + 1),
          reason: 'Composer hidden behind the on-screen keyboard',
        );
        expect(tester.takeException(), isNull);
        // Collapsing chrome is a layout choice, not a consent change.
        expect(find.text('External AI requests are off'), findsNothing);
      },
    );

    testWidgets(
      'AI composer accepts long multiline input at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (WidgetTester tester) async {
        _configureView(tester, size);
        await _pumpShell(tester, keyboard: 300);
        await _openAiAssistant(tester);

        const String longMessage = 'Line one\nLine two\nLine three\n'
            'A deliberately long final line that must wrap instead of '
            'pushing the send button off the screen.';
        await tester.enterText(_composerFinder(), longMessage);
        await tester.pumpAndSettle();

        final Rect composer = tester.getRect(_composerFinder());
        expect(composer.bottom, lessThanOrEqualTo(size.height - 300 + 1));
        expect(find.widgetWithText(FilledButton, 'Send'), findsOneWidget);
        final Rect send =
            tester.getRect(find.widgetWithText(FilledButton, 'Send'));
        expect(send.bottom, lessThanOrEqualTo(size.height - 300 + 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('bottom navigation respects gesture navigation inset',
      (WidgetTester tester) async {
    const Size size = Size(360, 800);
    _configureView(tester, size, gestureInset: 16);
    await _pumpShell(tester);

    final Finder nav = find.byType(FBottomNavigationBar);
    expect(nav, findsOneWidget);
    expect(
      tester.getRect(nav).bottom,
      lessThanOrEqualTo(size.height - 16 + 1),
      reason: 'Navigation rendered behind the gesture area',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('AI layout survives large accessibility text',
      (WidgetTester tester) async {
    _configureView(tester, const Size(360, 800));
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(
        () => tester.platformDispatcher.clearTextScaleFactorTestValue());

    await _pumpShell(tester);
    await _openAiAssistant(tester);

    expect(_composerFinder(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Settings layout survives large accessibility text',
      (WidgetTester tester) async {
    _configureView(tester, const Size(360, 800), statusBar: 32);
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(
        () => tester.platformDispatcher.clearTextScaleFactorTestValue());

    await _pumpShell(tester);
    await _openSettings(tester);

    expect(
      tester.getRect(find.text('Display density')).width,
      greaterThan(140),
    );
    expect(
      tester.getRect(find.text('Spacing and control sizing.')).width,
      greaterThan(140),
    );
    expect(tester.takeException(), isNull);
  });

  // Global responsive audit. Every destination is exercised with large text,
  // a status-bar cutout and gesture-navigation inset at all supported phone
  // widths. Layout exceptions are asserted after each route so the failing
  // destination is obvious instead of hiding behind a later navigation.
  for (final Size size in _phoneSizes) {
    final String viewport = '${size.width.toInt()}x${size.height.toInt()}';

    const Map<String, String?> primaryDestinations = <String, String?>{
      'Home': null,
      'Devices': 'Devices',
      'Display': 'Display Studio',
      'Diagnostics': 'Diagnostics & Logs',
    };
    for (final MapEntry<String, String?> destination
        in primaryDestinations.entries) {
      testWidgets(
        'large text audit: ${destination.key} at $viewport',
        (WidgetTester tester) async {
          _configureView(
            tester,
            size,
            statusBar: 32,
            gestureInset: 16,
          );
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(
              () => tester.platformDispatcher.clearTextScaleFactorTestValue());

          await _pumpShell(tester);
          await _openPrimaryDestination(tester, destination.key);

          if (destination.value == null) {
            expect(find.byType(AppTopBar), findsOneWidget);
          } else {
            expect(find.text(destination.value!), findsWidgets);
          }
          expect(tester.takeException(), isNull);
        },
      );
    }

    const Map<String, String> moreDestinations = <String, String>{
      'Family Directory': 'Family Directory',
      'Profiles & Security': 'Profiles & Security',
      'Voice & Audio': 'Voice & Audio',
      'Integrations': 'Integrations',
      'AI Assistant': 'AURA Assistant',
      'AURA Memory': 'AURA Memory',
      'Automations': 'Automations',
      'Notifications': 'Notification Centre',
      'Firmware & Updates': 'Firmware & Updates',
      'Settings': 'Settings',
    };
    for (final MapEntry<String, String> destination
        in moreDestinations.entries) {
      testWidgets(
        'large text audit: ${destination.key} at $viewport',
        (WidgetTester tester) async {
          _configureView(
            tester,
            size,
            statusBar: 32,
            gestureInset: 16,
          );
          tester.platformDispatcher.textScaleFactorTestValue = 1.3;
          addTearDown(
              () => tester.platformDispatcher.clearTextScaleFactorTestValue());

          await _pumpShell(tester);
          await _openMoreDestination(tester, destination.key);

          expect(find.text(destination.value), findsWidgets);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
