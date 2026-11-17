import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:flutter_test/flutter_test.dart';

ApiRequestRecord _record(int index) => ApiRequestRecord(
      path: '/api/system',
      startedAt: DateTime(2026, 1, 1, 12, 0, index),
      duration: Duration(milliseconds: 50 + index),
      statusCode: 200,
    );

void main() {
  test('records entries newest first', () {
    final DiagnosticsNotifier notifier = DiagnosticsNotifier();
    addTearDown(notifier.dispose);

    notifier.record(_record(1));
    notifier.record(_record(2));

    expect(notifier.state, hasLength(2));
    expect(notifier.state.first.duration.inMilliseconds, 52);
  });

  test('ring buffer is capped at 100 entries', () {
    final DiagnosticsNotifier notifier = DiagnosticsNotifier();
    addTearDown(notifier.dispose);

    for (int i = 0; i < 150; i++) {
      notifier.record(_record(i));
    }

    expect(notifier.state, hasLength(DiagnosticsNotifier.maxRecords));
    expect(notifier.state.first.duration.inMilliseconds, 199);
  });

  test('clear removes all entries', () {
    final DiagnosticsNotifier notifier = DiagnosticsNotifier();
    addTearDown(notifier.dispose);

    notifier.record(_record(1));
    notifier.clear();

    expect(notifier.state, isEmpty);
  });
}
