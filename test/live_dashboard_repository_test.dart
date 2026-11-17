import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/dashboard/data/live_dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/diagnostics/domain/sampler_health.dart';
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
      'security': <String, dynamic>{
        'firewallEnabled': true,
        'firewallState': 'enabled',
      },
      'sampler': <String, dynamic>{
        'ready': true,
        'healthy': true,
        'consecutiveFailures': 0,
        'lastSuccessAt': '2026-11-17T12:00:00.000Z',
        'lastError': null,
      },
    };

void main() {
  test('local API response does not imply an AURA device is connected',
      () async {
    final DashboardSnapshot snapshot =
        await LiveDashboardRepository(client: FakeAuraApiClient(_payload()))
            .loadDashboard();

    expect(snapshot.localApiOnline, isTrue);
    expect(snapshot.coreLink, CoreLinkState.notLinked);
    expect(snapshot.devices, isEmpty);
  });

  test('Windows host readings stay in system metrics, not device records',
      () async {
    final DashboardSnapshot snapshot =
        await LiveDashboardRepository(client: FakeAuraApiClient(_payload()))
            .loadDashboard();

    expect(snapshot.system.hostName, 'TEST-PC');
    expect(snapshot.system.cpuPercent, 42.5);
    expect(snapshot.system.batteryPercent, 77);
    expect(snapshot.averageBatteryPercent, isNull);
  });

  test('failed firewall probe is unavailable, never disabled', () async {
    final Map<String, dynamic> payload = _payload();
    payload['security'] = <String, dynamic>{
      'firewallEnabled': null,
      'firewallState': 'unavailable',
    };
    final DashboardSnapshot snapshot =
        await LiveDashboardRepository(client: FakeAuraApiClient(payload))
            .loadDashboard();

    expect(snapshot.system.firewallState, FirewallReadiness.unavailable);
    expect(snapshot.system.firewallEnabled, isNull);
    expect(
      snapshot.activity.any(
        (event) => event.title == 'Windows firewall status unavailable',
      ),
      isTrue,
    );
    expect(
      snapshot.activity.any((event) => event.title.contains('disabled')),
      isFalse,
      reason: 'an unavailable probe must not be reported as disabled',
    );
  });

  test('sampler health is reported separately from request outcomes', () async {
    SamplerHealth? captured;
    await LiveDashboardRepository(
      client: FakeAuraApiClient(_payload()),
      onSamplerHealth: (SamplerHealth health) => captured = health,
    ).loadDashboard();

    expect(captured, isNotNull);
    expect(captured!.status, SamplerReadiness.ready);
    expect(captured!.lastSuccessAt, isNotNull);
    expect(captured!.consecutiveFailures, 0);
    expect(captured!.toJson()['ready'], isTrue);
  });

  test('activity events are labelled as host observations', () async {
    final DashboardSnapshot snapshot =
        await LiveDashboardRepository(client: FakeAuraApiClient(_payload()))
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
