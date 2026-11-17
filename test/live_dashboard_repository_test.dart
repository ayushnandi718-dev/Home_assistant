import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/dashboard/data/live_dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAuraApiClient extends AuraApiClient {
  FakeAuraApiClient(this.payload) : super(baseUrl: 'http://127.0.0.1:8765');

  final Map<String, dynamic> payload;

  @override
  Future<Map<String, dynamic>> getJson(String path) async => payload;
}

Map<String, dynamic> _payload() => <String, dynamic>{
      'generatedAt': '2026-11-17T12:00:00.000Z',
      'host': <String, dynamic>{
        'name': 'TEST-PC',
        'os': 'Windows test build',
        'bootTime': '2026-11-17T10:00:00.000Z',
        'uptimeSeconds': 7200,
      },
      'cpu': <String, dynamic>{
        'usagePercent': 42.5,
        'perCore': <dynamic>[40, 45],
        'cores': 2,
        'frequencyMHz': 2400,
      },
      'memory': <String, dynamic>{
        'totalBytes': 8 * 1024 * 1024 * 1024,
        'usedBytes': 4 * 1024 * 1024 * 1024,
        'availableBytes': 4 * 1024 * 1024 * 1024,
        'usagePercent': 50,
      },
      'disk': <String, dynamic>{
        'path': 'C:\\',
        'totalBytes': 100 * 1024 * 1024 * 1024,
        'usedBytes': 40 * 1024 * 1024 * 1024,
        'freeBytes': 60 * 1024 * 1024 * 1024,
        'usagePercent': 40,
      },
      'network': <String, dynamic>{
        'bytesSent': 1000,
        'bytesReceived': 2000,
        'sentBytesPerSecond': 10,
        'receivedBytesPerSecond': 20,
        'activeInterfaces': 1,
      },
      'battery': <String, dynamic>{
        'percent': 77,
        'plugged': true,
        'secondsLeft': null,
      },
      'processCount': 123,
      'topProcesses': <dynamic>[],
      'security': <String, dynamic>{'firewallEnabled': true},
    };

void main() {
  test('local API response does not imply an AURA device is connected',
      () async {
    final DashboardSnapshot snapshot = await LiveDashboardRepository(
            client: FakeAuraApiClient(_payload()))
        .loadDashboard();

    expect(snapshot.localApiOnline, isTrue);
    expect(snapshot.coreLink, CoreLinkState.notLinked);
    expect(snapshot.devices, isEmpty);
  });

  test('Windows host readings stay in system metrics, not device records',
      () async {
    final DashboardSnapshot snapshot = await LiveDashboardRepository(
            client: FakeAuraApiClient(_payload()))
        .loadDashboard();

    expect(snapshot.system.hostName, 'TEST-PC');
    expect(snapshot.system.cpuPercent, 42.5);
    expect(snapshot.system.batteryPercent, 77);
    expect(snapshot.averageBatteryPercent, isNull);
  });

  test('activity events are labelled as host observations', () async {
    final DashboardSnapshot snapshot = await LiveDashboardRepository(
            client: FakeAuraApiClient(_payload()))
        .loadDashboard();

    expect(snapshot.activity, isNotEmpty);
    expect(
      snapshot.activity.every(
        (event) => event.detail.contains('TEST-PC'),
      ),
      isTrue,
    );
  });
}
