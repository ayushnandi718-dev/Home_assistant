import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';

/// Network boundary used by the lifecycle service. Kept abstract so tests can
/// simulate health, timeouts and unrelated services without opening sockets.
abstract class TelemetryApiProbe {
  Future<TelemetryHealthResult> check();

  /// Requests a graceful Python shutdown when the API exposes the optional
  /// localhost-only control route. Returns false when it is unavailable.
  Future<bool> requestShutdown();
}

class DartTelemetryApiProbe implements TelemetryApiProbe {
  DartTelemetryApiProbe({
    required this.config,
    HttpClient? client,
  }) : _client = client ?? HttpClient();

  final TelemetryApiConfig config;
  final HttpClient _client;

  @override
  Future<TelemetryHealthResult> check() async {
    try {
      final HttpClientRequest request =
          await _client.getUrl(config.healthUri).timeout(config.healthTimeout);
      final HttpClientResponse response =
          await request.close().timeout(config.healthTimeout);
      final String body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(config.healthTimeout);
      if (response.statusCode >= 200 &&
          response.statusCode < 300 &&
          _isCompatible(body)) {
        return TelemetryHealthResult.healthyResult;
      }
      return TelemetryHealthResult.unrelatedService;
    } on Object {
      return _probePort();
    }
  }

  @override
  Future<bool> requestShutdown() async {
    try {
      final HttpClientRequest request = await _client
          .postUrl(config.shutdownUri)
          .timeout(config.healthTimeout);
      final HttpClientResponse response =
          await request.close().timeout(config.healthTimeout);
      await response.drain<List<int>>().timeout(config.healthTimeout);
      return response.statusCode >= 200 && response.statusCode < 300;
    } on Object {
      return false;
    }
  }

  Future<TelemetryHealthResult> _probePort() async {
    try {
      final Socket socket = await Socket.connect(
        config.host,
        config.port,
        timeout: config.healthTimeout,
      );
      socket.destroy();
      return TelemetryHealthResult.unrelatedService;
    } on Object {
      return TelemetryHealthResult.unreachable;
    }
  }

  /// Requires a recognizable AURA/telemetry health payload. A plain 200 from
  /// another service on the same port is not treated as a compatible API.
  bool _isCompatible(String body) {
    final String normalized = body.trim().toLowerCase();
    if (normalized.isEmpty || normalized.length > 2048) return false;
    final bool auraMarker =
        normalized.contains('aura') && normalized.contains('telemetry');
    final bool healthyStatus = normalized.contains('"status"') &&
        (normalized.contains('ok') || normalized.contains('healthy'));
    return auraMarker && healthyStatus;
  }

  void close() => _client.close(force: true);
}
