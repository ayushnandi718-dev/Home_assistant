import 'dart:async';

import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/core/services/clock_service.dart';
import 'package:aura_hub/features/dashboard/data/no_panel_command_transport.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/scene_action.dart';
import 'package:aura_hub/features/dashboard/domain/scene_command.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/dashboard/presentation/scene_actions_provider.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/mobile_time_tile.dart';
import 'package:aura_hub/features/devices/data/local_device_repository.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/features/weather/domain/weather_location.dart';
import 'package:aura_hub/features/weather/domain/weather_repository.dart';
import 'package:aura_hub/features/weather/domain/weather_snapshot.dart';
import 'package:aura_hub/features/weather/presentation/weather_providers.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

class _OfflineDashboardRepository implements DashboardRepository {
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

class _MutableClock implements AuraClock {
  _MutableClock(this._now);

  DateTime _now;

  void advance(Duration duration) => _now = _now.add(duration);

  @override
  DateTime nowUtc() => _now.toUtc();

  @override
  DateTime nowDeviceLocal() => _now;

  @override
  String get deviceTimeZoneName => 'Test zone';

  @override
  Duration get deviceUtcOffset => Duration.zero;

  @override
  DateTime nowIn(String ianaIdentifier) => _now;

  @override
  bool supportsZone(String ianaIdentifier) => true;

  @override
  String formatIn(
    DateTime instant, {
    required String ianaIdentifier,
    String locale = 'en_US',
  }) =>
      instant.toIso8601String();
}

class _FakeWeatherRepository implements WeatherRepository {
  _FakeWeatherRepository({this.error, this.gate});

  Object? error;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<WeatherSnapshot> fetchCurrent(WeatherLocation location) async {
    calls++;
    await gate?.future;
    final Object? failure = error;
    if (failure != null) throw failure;
    return WeatherSnapshot(
      temperatureCelsius: 21.4,
      code: 0,
      locationLabel: location.label,
      observedAt: DateTime.utc(2026, 11, 21, 9, 30),
    );
  }
}

class _FakeSceneTransport implements SceneCommandTransport {
  _FakeSceneTransport({this.result, this.gate});

  SceneCommandResult? result;
  Completer<void>? gate;
  int calls = 0;

  @override
  Future<SceneCommandResult> send(SceneAction action) async {
    calls++;
    await gate?.future;
    return result ??
        const SceneCommandResult.unavailable('No transport is available.');
  }
}

class _FakeDeviceRepository implements DeviceRepository {
  _FakeDeviceRepository(this.devices);

  final List<AuraDevice> devices;

  @override
  Future<List<AuraDevice>> fetchDevices() async => devices;

  @override
  Future<DeviceDiscoveryResult> discover() async =>
      const DeviceDiscoveryResult.unavailable('No transport.');

  @override
  Future<DevicePairingResult> pair(String deviceId) async =>
      const DevicePairingResult.unavailable('No transport.');

  @override
  Future<DeviceLinkState> currentLink() async =>
      const DeviceLinkState(status: DeviceLinkStatus.notPaired);
}

AuraDevice _device({
  required String id,
  required DeviceConnectionState state,
}) =>
    AuraDevice(
      id: id,
      name: 'Panel $id',
      model: 'AURA display',
      firmwareVersion: '0',
      transport: DeviceTransport.wifi,
      connectionState: state,
      connectionQuality: DeviceConnectionQuality.unknown,
      isDemo: false,
    );

WeatherLocation get _location => const WeatherLocation(
      label: 'Test Town',
      latitude: 12.34,
      longitude: 56.78,
    );

WeatherLocationController _locationController(WeatherLocation? location) {
  final WeatherLocationController controller = WeatherLocationController();
  if (location != null) controller.state = location;
  return controller;
}

DeviceLinkController _linkController(DeviceLinkStatus status) {
  final DeviceLinkController controller =
      DeviceLinkController(const LocalDeviceRepository());
  controller.state = DeviceLinkState(
    status: status,
    deviceId: status == DeviceLinkStatus.connected ? 'panel-1' : null,
  );
  return controller;
}

Future<void> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(393, 852),
  bool always24Hour = false,
  bool settle = true,
  List<Override> overrides = const <Override>[],
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final MediaQueryData media = MediaQueryData.fromView(tester.view).copyWith(
    alwaysUse24HourFormat: always24Hour,
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        dashboardRepositoryProvider
            .overrideWithValue(_OfflineDashboardRepository()),
        weatherLocationProvider.overrideWith(
          (Ref ref) => _locationController(null),
        ),
        ...overrides,
      ],
      child: MediaQuery(data: media, child: const AuraApp()),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // Indeterminate progress indicators animate forever; settle would time out.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('weather', () {
    test('location parsing rejects invented or out-of-range values', () {
      expect(
        () => WeatherLocation.parse(
          label: '',
          latitude: '12',
          longitude: '56',
        ),
        throwsFormatException,
      );
      expect(
        () => WeatherLocation.parse(
          label: 'Test',
          latitude: '120',
          longitude: '56',
        ),
        throwsFormatException,
      );
      final WeatherLocation parsed = WeatherLocation.parse(
        label: '  Test Town  ',
        latitude: '12.34',
        longitude: '-56.78',
      );
      expect(parsed.label, 'Test Town');
      expect(parsed.latitude, 12.34);
      expect(parsed.longitude, -56.78);
    });

    test('weather codes map to honest labels', () {
      expect(WeatherCondition.fromCode(0).label, 'Clear sky');
      expect(WeatherCondition.fromCode(2).label, 'Partly cloudy');
      expect(WeatherCondition.fromCode(45).label, 'Fog');
      expect(WeatherCondition.fromCode(61).label, 'Rain');
      expect(WeatherCondition.fromCode(77).label, 'Snow');
      expect(WeatherCondition.fromCode(95).label, 'Thunderstorm');
      expect(WeatherCondition.fromCode(999).label, 'Thunderstorm');
      expect(WeatherCondition.fromCode(80).label, 'Condition unavailable');
    });

    testWidgets('loading becomes a real observation',
        (WidgetTester tester) async {
      final Completer<void> gate = Completer<void>();
      final _FakeWeatherRepository repository =
          _FakeWeatherRepository(gate: gate);
      await _pumpApp(
        tester,
        settle: false,
        overrides: <Override>[
          weatherLocationProvider.overrideWith(
            (Ref ref) => _locationController(_location),
          ),
          weatherRepositoryProvider.overrideWithValue(repository),
        ],
      );

      expect(find.text('Loading…'), findsOneWidget);
      gate.complete();
      await tester.pumpAndSettle();

      expect(find.text('21°'), findsOneWidget);
      expect(find.textContaining('Test Town'), findsWidgets);
      expect(find.textContaining('Clear sky'), findsOneWidget);
    });

    testWidgets('failed fetch shows an honest unavailable state',
        (WidgetTester tester) async {
      await _pumpApp(
        tester,
        overrides: <Override>[
          weatherLocationProvider.overrideWith(
            (Ref ref) => _locationController(_location),
          ),
          weatherRepositoryProvider.overrideWithValue(
            _FakeWeatherRepository(
              error:
                  const WeatherFetchException('Weather service unavailable.'),
            ),
          ),
        ],
      );

      final Finder tile = find.byKey(const ValueKey<String>('weather-tile'));
      expect(
        find.descendant(of: tile, matching: find.text('Unavailable')),
        findsOneWidget,
      );
      expect(
        find.text('Weather service unavailable.'),
        findsOneWidget,
      );
    });

    test('a failed refresh keeps the last successful observation', () async {
      final _FakeWeatherRepository repository = _FakeWeatherRepository();
      final WeatherController controller = WeatherController(repository);
      controller.observe(_location);
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(controller.state.status, WeatherStatus.success);
      final WeatherSnapshot cached = controller.state.snapshot!;

      repository.error =
          const WeatherFetchException('Weather service unavailable.');
      await controller.refresh();

      expect(controller.state.status, WeatherStatus.error);
      expect(controller.state.snapshot, same(cached));
      controller.dispose();
    });
  });

  group('clock', () {
    test('respects the platform 12/24-hour preference', () {
      final DateTime evening = DateTime(2026, 11, 21, 21, 5);
      expect(
        formatMobileClock(evening, use24Hour: true),
        '21:05',
      );
      expect(
        formatMobileClock(evening, use24Hour: false),
        '9:05 PM',
      );
    });

    testWidgets('live tile ticks without rebuilding the whole dashboard',
        (WidgetTester tester) async {
      final _MutableClock clock = _MutableClock(DateTime(2026, 11, 21, 9, 30));
      await _pumpApp(
        tester,
        always24Hour: true,
        overrides: <Override>[
          displayClockProvider.overrideWithValue(clock),
        ],
      );

      expect(find.text('09:30'), findsOneWidget);
      clock.advance(const Duration(minutes: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(find.text('09:31'), findsOneWidget);
      expect(find.text('09:30'), findsNothing);
    });
  });

  group('panels and scenes', () {
    testWidgets('panel tile stays honest when no panel is paired',
        (WidgetTester tester) async {
      await _pumpApp(tester);

      final Finder tile = find.byKey(const ValueKey<String>('panel-tile'));
      expect(
        find.descendant(of: tile, matching: find.text('Not paired')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: tile, matching: find.text('Tap to pair')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('panel-wifi-tile')),
          matching: find.text('Not paired'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('only registered online devices are counted',
        (WidgetTester tester) async {
      await _pumpApp(
        tester,
        overrides: <Override>[
          deviceRepositoryProvider.overrideWithValue(
            _FakeDeviceRepository(<AuraDevice>[
              _device(id: 'a', state: DeviceConnectionState.online),
              _device(id: 'b', state: DeviceConnectionState.offline),
            ]),
          ),
        ],
      );

      final Finder tile = find.byKey(const ValueKey<String>('devices-tile'));
      expect(
        find.descendant(of: tile, matching: find.text('1')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.text('registered AURA devices'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('scene action waits for a real acknowledgement',
        (WidgetTester tester) async {
      final Completer<void> gate = Completer<void>();
      final _FakeSceneTransport transport = _FakeSceneTransport(
        gate: gate,
        result: const SceneCommandResult.acknowledged('Panel acknowledged it.'),
      );
      await _pumpApp(
        tester,
        overrides: <Override>[
          deviceLinkProvider.overrideWith(
            (Ref ref) => _linkController(DeviceLinkStatus.connected),
          ),
          sceneCommandTransportProvider.overrideWithValue(transport),
        ],
      );

      final Finder pill =
          find.byKey(const ValueKey<String>('scene-pill-nightMode'));
      await tester
          .tap(find.descendant(of: pill, matching: find.byType(InkWell)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(transport.calls, 1);
      expect(find.text('Waiting for panel acknowledgement…'), findsOneWidget);

      // A second tap while the first command is pending is ignored.
      await tester
          .tap(find.descendant(of: pill, matching: find.byType(InkWell)));
      await tester.pump();
      expect(transport.calls, 1);

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Panel acknowledged it.'), findsOneWidget);
      expect(find.text('Waiting for panel acknowledgement…'), findsNothing);
    });

    testWidgets('unacknowledged transport never reports success',
        (WidgetTester tester) async {
      await _pumpApp(
        tester,
        overrides: <Override>[
          deviceLinkProvider.overrideWith(
            (Ref ref) => _linkController(DeviceLinkStatus.connected),
          ),
          sceneCommandTransportProvider
              .overrideWithValue(const NoPanelCommandTransport()),
        ],
      );

      final Finder pill =
          find.byKey(const ValueKey<String>('scene-pill-restartPanel'));
      // The fixed mobile navigation overlays the bottom of the scroll view. On
      // runners with taller font metrics the last pill can sit underneath it,
      // so scroll it clear before tapping. This keeps the test about transport
      // behaviour rather than tap geometry.
      final Finder scrollable = find
          .ancestor(
            of: pill,
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.drag(scrollable, const Offset(0, -160));
      await tester.pumpAndSettle();
      await tester
          .tap(find.descendant(of: pill, matching: find.byType(InkWell)));
      await tester.pumpAndSettle();

      expect(
        find.text('No ESP32 command transport is available yet.'),
        findsOneWidget,
      );
    });
  });

  group('layout and activity', () {
    for (final double width in <double>[360, 393, 476]) {
      testWidgets('tile grid fits ${width.toInt()}px without overflow',
          (WidgetTester tester) async {
        await _pumpApp(tester, size: Size(width, 800));

        for (final String key in <String>[
          'weather-tile',
          'time-tile',
          'panel-tile',
          'devices-tile',
          'phone-battery-tile',
          'panel-last-seen-tile',
        ]) {
          final Rect rect = tester.getRect(find.byKey(ValueKey<String>(key)));
          expect(rect.left, greaterThanOrEqualTo(-1), reason: key);
          expect(rect.right, lessThanOrEqualTo(width + 1), reason: key);
        }

        final Rect weather =
            tester.getRect(find.byKey(const ValueKey<String>('weather-tile')));
        final Rect time =
            tester.getRect(find.byKey(const ValueKey<String>('time-tile')));
        expect(weather.right, lessThan(time.left));
        expect(weather.top, time.top);

        final Rect panel =
            tester.getRect(find.byKey(const ValueKey<String>('panel-tile')));
        final Rect devices =
            tester.getRect(find.byKey(const ValueKey<String>('devices-tile')));
        expect(panel.right, lessThan(devices.left));
        expect(panel.top, greaterThan(weather.bottom));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('phone battery has an honest unavailable state',
        (WidgetTester tester) async {
      await _pumpApp(tester);

      final Finder tile =
          find.byKey(const ValueKey<String>('phone-battery-tile'));
      expect(
        find.descendant(of: tile, matching: find.text('Unavailable')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.text('No battery API on this build'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('recent activity has a clean empty state',
        (WidgetTester tester) async {
      await _pumpApp(
        tester,
        overrides: <Override>[
          deviceLinkProvider.overrideWith(
            (Ref ref) => _linkController(DeviceLinkStatus.notPaired),
          ),
          diagnosticEventsProvider.overrideWith(
            (Ref ref) => DiagnosticEventsNotifier(),
          ),
        ],
      );

      expect(find.text('No recent activity'), findsOneWidget);
      expect(
        find.textContaining('Real device connection and pairing events'),
        findsOneWidget,
      );
    });

    testWidgets('FAMILY dashboard never renders private AYUSH data',
        (WidgetTester tester) async {
      await _pumpApp(tester);

      expect(find.textContaining('FAMILY workspace'), findsWidgets);
      expect(find.textContaining('AYUSH workspace'), findsNothing);
    });

    testWidgets('last tile scrolls clear of the floating bottom navigation',
        (WidgetTester tester) async {
      await _pumpApp(tester, size: const Size(476, 900));

      await tester.drag(
        find.byType(SingleChildScrollView).first,
        const Offset(0, -4000),
      );
      await tester.pumpAndSettle();

      final Finder recentCard = find
          .ancestor(
            of: find.text('Recent activity'),
            matching: find.byType(SurfaceCard),
          )
          .first;
      final double cardBottom = tester.getBottomRight(recentCard).dy;
      final double navTop = tester
          .getTopLeft(
            find.byType(FBottomNavigationBar),
          )
          .dy;
      expect(cardBottom, lessThan(navTop));
    });
  });
}
