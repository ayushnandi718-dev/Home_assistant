import 'dart:io';

import 'package:aura_hub/core/telemetry/telemetry_log_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('aura-telemetry-log-test-');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('redacts credentials, URLs, home paths and long numbers', () {
    final String sanitized = redactTelemetryLogText(
      'api_key=super-secret Authorization: Bearer abc.def '
      'https://example.com/telemetry C:\\Users\\Alice\\secret '
      '/home/bob/private pin: 123456',
    );

    expect(sanitized, contains('api_key=[REDACTED]'));
    expect(sanitized, contains('Bearer [REDACTED]'));
    expect(sanitized, contains('[URL]'));
    expect(sanitized, contains(r'C:\Users\[USER]'));
    expect(sanitized, contains('/home/[USER]'));
    expect(sanitized, contains('pin=[REDACTED]'));
    expect(sanitized, isNot(contains('super-secret')));
    expect(sanitized, isNot(contains('abc.def')));
    expect(sanitized, isNot(contains('Alice')));
    expect(sanitized, isNot(contains('bob')));
    expect(sanitized, isNot(contains('123456')));
  });

  test('persists sanitized events and rotates log files', () async {
    final TelemetryApiLogStore store = TelemetryApiLogStore(
      directory: root,
      maxBytes: 1,
      maxFiles: 2,
    );

    await store.append('first event', detail: 'pin=987654');
    await store.append('second event', detail: 'ok');
    await store.append('third event', detail: 'ok');

    final List<String> recent = await store.readRecent(limit: 10);
    expect(recent, isNotEmpty);
    expect(recent.first, contains('third event'));
    expect(recent.join('\n'), contains('second event'));
    expect(recent.join('\n'), isNot(contains('first event')));
    expect(recent.join('\n'), isNot(contains('987654')));

    final File active = File(
      '${root.path}${Platform.pathSeparator}telemetry_api.log',
    );
    final File rotated = File('${active.path}.1');
    expect(active.existsSync(), isTrue);
    expect(rotated.existsSync(), isTrue);
    expect(File('${active.path}.2').existsSync(), isFalse);
  });

  test('synchronous append persists a sanitized shutdown line immediately', () {
    final TelemetryApiLogStore store = TelemetryApiLogStore(directory: root);

    store.appendSync('shutdown requested', detail: 'api_key=secret');

    final File active = File(
      '${root.path}${Platform.pathSeparator}telemetry_api.log',
    );
    final String content = active.readAsStringSync();
    expect(content, contains('shutdown requested'));
    expect(content, contains('api_key=[REDACTED]'));
    expect(content, isNot(contains('secret')));
  });

  test('three-file rotation keeps both rotated generations', () async {
    final TelemetryApiLogStore store = TelemetryApiLogStore(
      directory: root,
      maxBytes: 1,
      maxFiles: 3,
    );

    await store.append('first event');
    await store.append('second event');
    await store.append('third event');

    final List<String> recent = await store.readRecent(limit: 10);
    expect(recent.join('\n'), contains('third event'));
    expect(recent.join('\n'), contains('second event'));
    expect(recent.join('\n'), contains('first event'));

    final File active = File(
      '${root.path}${Platform.pathSeparator}telemetry_api.log',
    );
    expect(File('${active.path}.1').existsSync(), isTrue);
    expect(File('${active.path}.2').existsSync(), isTrue);
  });
}
