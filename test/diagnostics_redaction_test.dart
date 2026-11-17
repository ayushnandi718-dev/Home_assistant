import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/core/utilities/redaction.dart';
import 'package:aura_hub/features/diagnostics/domain/sampler_health.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redaction removes URLs and local paths', () {
    final String safe = Redaction.sanitise(
      'Cannot reach http://127.0.0.1:8765 at C:\\Users\\ayush\\secret.txt',
    );
    expect(safe, isNot(contains('http://')));
    expect(safe, isNot(contains('C:\\')));
    expect(safe, isNot(contains('secret')));
    expect(safe, contains('<url>'));
    expect(safe, contains('<path>'));
  });

  test('API request records sanitise errors when serialised', () {
    final ApiRequestRecord record = ApiRequestRecord(
      path: '/api/system',
      startedAt: DateTime(2026, 1, 1),
      duration: const Duration(milliseconds: 25),
      statusCode: 500,
      error: 'AURA API returned HTTP 500 at http://127.0.0.1:8765',
    );
    final Map<String, dynamic> json = record.toJson();
    expect(json['path'], '/api/system');
    expect(json['error'], isNot(contains('http://')));
    expect(json['succeeded'], isFalse);
  });

  test('sampler health parses unavailable state and sanitises error types', () {
    final SamplerHealth health = SamplerHealth.fromJson(<String, dynamic>{
      'ready': false,
      'healthy': false,
      'consecutiveFailures': 2,
      'lastSuccessAt': null,
      'lastFailureAt': '2026-11-17T12:00:00.000Z',
      'lastError': 'RuntimeError at C:\\Users\\ayush\\token',
    });

    expect(health.status, SamplerReadiness.initializing);
    expect(health.hasFailure, isTrue);
    expect(health.lastSuccessAt, isNull);
    expect(health.lastFailureAt, isNotNull);
    expect(health.toJson()['lastError'], isNot(contains('C:\\')));
    expect(health.toJson()['lastError'], contains('RuntimeError'));
  });

  test('sampler history is separate and bounded', () {
    final SamplerDiagnosticsNotifier notifier = SamplerDiagnosticsNotifier();
    addTearDown(notifier.dispose);

    for (int i = 0; i < 60; i++) {
      notifier.observe(
        SamplerHealth(
          ready: true,
          healthy: false,
          consecutiveFailures: 1,
          lastError: 'RuntimeError',
          observedAt: DateTime(2026, 1, 1, 0, 0, i),
        ),
      );
    }

    expect(notifier.state, hasLength(SamplerDiagnosticsNotifier.maxRecords));
    expect(
      notifier.state.every((SamplerHealth sample) => sample.hasFailure),
      isTrue,
    );
    expect(notifier.state.first.observedAt.second, 59);

    notifier.clear();
    expect(notifier.state, isEmpty);
  });
}
