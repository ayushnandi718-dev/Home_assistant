import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

Future<HttpServer> _startServer({
  required int statusCode,
  required String body,
  Duration delay = Duration.zero,
}) async {
  final HttpServer server = await HttpServer.bind(
    InternetAddress.loopbackIPv4,
    0,
  );
  server.listen((HttpRequest request) async {
    if (delay > Duration.zero) {
      await Future<void>.delayed(delay);
    }
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    await request.response.close();
  });
  return server;
}

void main() {
  test('successful request is recorded as a success', () async {
    final HttpServer server = await _startServer(
      statusCode: 200,
      body: jsonEncode(<String, dynamic>{'ok': true}),
    );
    addTearDown(() => server.close(force: true));

    final List<ApiRequestRecord> records = <ApiRequestRecord>[];
    final AuraApiClient client = AuraApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      onRequest: records.add,
    );

    final Map<String, dynamic> payload = await client.getJson('/api/health');
    expect(payload['ok'], isTrue);
    expect(records, hasLength(1));
    expect(records.single.succeeded, isTrue);
    expect(records.single.statusCode, 200);
    expect(records.single.error, isNull);
    expect(records.single.path, '/api/health');
    expect(records.single.toJson()['durationMs'], isA<int>());
  });

  test('HTTP error is recorded as a failure', () async {
    final HttpServer server = await _startServer(
      statusCode: 500,
      body: '{"error":"boom"}',
    );
    addTearDown(() => server.close(force: true));

    final List<ApiRequestRecord> records = <ApiRequestRecord>[];
    final AuraApiClient client = AuraApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      onRequest: records.add,
    );

    await expectLater(
      client.getJson('/api/system'),
      throwsA(isA<AuraApiException>()),
    );
    expect(records, hasLength(1));
    expect(records.single.succeeded, isFalse);
    expect(records.single.statusCode, 500);
    expect(records.single.error, contains('HTTP 500'));
  });

  test('timeout is recorded and surfaced as AuraApiException', () async {
    final HttpServer server = await _startServer(
      statusCode: 200,
      body: '{}',
      delay: const Duration(seconds: 3),
    );
    addTearDown(() => server.close(force: true));

    final List<ApiRequestRecord> records = <ApiRequestRecord>[];
    final AuraApiClient client = AuraApiClient(
      baseUrl: 'http://127.0.0.1:${server.port}',
      timeout: const Duration(milliseconds: 150),
      onRequest: records.add,
    );

    await expectLater(
      client.getJson('/api/system'),
      throwsA(
        isA<AuraApiException>().having(
          (AuraApiException e) => e.message,
          'message',
          contains('did not respond in time'),
        ),
      ),
    );
    expect(records, hasLength(1));
    expect(records.single.succeeded, isFalse);
    expect(records.single.error, contains('Timed out'));
  });
}
