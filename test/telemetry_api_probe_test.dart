import 'dart:async';
import 'dart:io';

import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_probe.dart';
import 'package:flutter_test/flutter_test.dart';

class _ProbeHarness {
  _ProbeHarness(this.server, this.probe);

  final HttpServer server;
  final DartTelemetryApiProbe probe;

  Future<void> dispose() async {
    probe.close();
    await server.close(force: true);
  }
}

Future<_ProbeHarness> _serveHealth(String body) async {
  final HttpServer server =
      await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((HttpRequest request) {
    request.response.headers.contentType = ContentType.json;
    request.response.write(body);
    unawaited(request.response.close());
  });
  final TelemetryApiConfig config = TelemetryApiConfig(
    host: '127.0.0.1',
    port: server.port,
    healthTimeout: const Duration(seconds: 2),
  );
  return _ProbeHarness(server, DartTelemetryApiProbe(config: config));
}

void main() {
  test('accepts the AURA telemetry health payload', () async {
    final _ProbeHarness harness = await _serveHealth(
      '{"status":"ok","service":"aura-local-telemetry","version":"1.1.0"}',
    );
    addTearDown(harness.dispose);

    final TelemetryHealthResult result = await harness.probe.check();

    expect(result.healthy, isTrue);
    expect(result.portOpen, isTrue);
  });

  test('does not adopt an unrelated 200 OK service on the same port', () async {
    final _ProbeHarness harness = await _serveHealth(
      '{"status":"ok","service":"unrelated-local-service"}',
    );
    addTearDown(harness.dispose);

    final TelemetryHealthResult result = await harness.probe.check();

    expect(result.healthy, isFalse);
    expect(result.portOpen, isTrue);
  });
}
