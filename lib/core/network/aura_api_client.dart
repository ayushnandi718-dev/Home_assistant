import 'dart:async';
import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/utilities/redaction.dart';

/// Thrown when the local AURA telemetry API cannot be reached or responds
/// with something unexpected.
class AuraApiException implements Exception {
  const AuraApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A single completed API request, recorded for the Diagnostics page.
/// Contains no credentials or payload contents.
class ApiRequestRecord {
  const ApiRequestRecord({
    required this.path,
    required this.startedAt,
    required this.duration,
    this.statusCode,
    this.error,
  });

  final String path;
  final DateTime startedAt;
  final Duration duration;
  final int? statusCode;
  final String? error;

  bool get succeeded => statusCode == 200 && error == null;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'path': path,
        'startedAt': startedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
        'statusCode': statusCode,
        if (error != null) 'error': Redaction.sanitise(error!),
        'succeeded': succeeded,
      };
}

typedef ApiRequestRecorder = void Function(ApiRequestRecord record);

/// Result of an explicit `GET /api/health` check.
///
/// This describes HTTP reachability only. Sampler fields are kept separate so
/// an HTTP 200 can never be mistaken for healthy background telemetry.
class ApiHealth {
  const ApiHealth({
    required this.checkedAt,
    required this.responseTime,
    this.status,
    this.service,
    this.version,
    this.samplerReady = false,
    this.samplerHealthy = false,
    this.samplerLastSuccessAt,
    this.samplerLastError,
    this.samplerConsecutiveFailures = 0,
    this.error,
  }) : reachable = error == null;

  factory ApiHealth.fromJson(
    Map<String, dynamic> json, {
    required DateTime checkedAt,
    required Duration responseTime,
  }) {
    final Object? sampler = json['sampler'];
    final Map<String, dynamic> samplerJson =
        sampler is Map<String, dynamic> ? sampler : <String, dynamic>{};
    return ApiHealth(
      checkedAt: checkedAt,
      responseTime: responseTime,
      status: json['status']?.toString(),
      service: json['service']?.toString(),
      version: json['version']?.toString(),
      samplerReady: samplerJson['ready'] == true,
      samplerHealthy: samplerJson['healthy'] == true,
      samplerLastSuccessAt: _date(samplerJson['lastSuccessAt']),
      samplerLastError: samplerJson['lastError']?.toString(),
      samplerConsecutiveFailures:
          (samplerJson['consecutiveFailures'] as num?)?.toInt() ?? 0,
    );
  }

  factory ApiHealth.failure({
    required DateTime checkedAt,
    required Duration responseTime,
    required String error,
  }) {
    return ApiHealth(
      checkedAt: checkedAt,
      responseTime: responseTime,
      error: error,
    );
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  final DateTime checkedAt;
  final Duration responseTime;
  final String? status;
  final String? service;
  final String? version;
  final bool samplerReady;
  final bool samplerHealthy;
  final DateTime? samplerLastSuccessAt;
  final String? samplerLastError;
  final int samplerConsecutiveFailures;
  final String? error;

  /// HTTP reachability, independent of sampler and device state.
  final bool reachable;

  String get samplerLabel {
    if (!samplerReady) return 'Initializing';
    return samplerHealthy ? 'Healthy' : 'Degraded';
  }

  /// Safe for diagnostics export: no URLs, paths or private payloads.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'checkedAt': checkedAt.toIso8601String(),
        'responseTimeMs': responseTime.inMilliseconds,
        'reachable': reachable,
        if (status != null) 'status': Redaction.sanitise(status!),
        if (service != null) 'service': Redaction.sanitise(service!),
        if (version != null) 'version': Redaction.sanitise(version!),
        'sampler': <String, dynamic>{
          'ready': samplerReady,
          'healthy': samplerHealthy,
          'label': samplerLabel,
          'lastSuccessAt': samplerLastSuccessAt?.toIso8601String(),
          'lastError': samplerLastError == null
              ? null
              : Redaction.sanitise(samplerLastError!),
          'consecutiveFailures': samplerConsecutiveFailures,
        },
        if (error != null) 'error': Redaction.sanitise(error!),
      };
}

typedef ApiHealthRecorder = void Function(ApiHealth health);

/// Minimal JSON client for the local AURA telemetry service.
class AuraApiClient {
  AuraApiClient({
    String? baseUrl,
    this.timeout = const Duration(seconds: 5),
    this.onRequest,
    this.onHealth,
    this.authToken,
  }) : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'AURA_API_BASE_URL',
              defaultValue: 'http://127.0.0.1:8765',
            );

  final String baseUrl;
  final Duration timeout;
  final ApiRequestRecorder? onRequest;
  final ApiHealthRecorder? onHealth;

  /// In-memory per-launch token for protected telemetry endpoints.
  ///
  /// Never persisted, logged or included in a request body or URL.
  final String? authToken;

  /// Base URL shown in the UI so it is always clear where data comes from.
  String get displayUrl => baseUrl.replaceFirst(RegExp(r'^https?://'), '');

  /// Verifies that the configured endpoint is the AURA local telemetry API.
  ///
  /// The request is recorded through [onRequest] and the parsed result (or its
  /// failure) through [onHealth], so Diagnostics keeps health checks separate
  /// from telemetry requests.
  Future<ApiHealth> checkHealth({ApiHealthRecorder? onHealth}) async {
    final DateTime startedAt = DateTime.now();
    final Stopwatch stopwatch = Stopwatch()..start();
    ApiHealth? result;

    try {
      final Map<String, dynamic> json = await getJson('/api/health');
      if (json['status'] != 'ok') {
        throw const AuraApiException(
          'AURA API health check did not report OK.',
        );
      }
      result = ApiHealth.fromJson(
        json,
        checkedAt: startedAt,
        responseTime: stopwatch.elapsed,
      );
      return result;
    } on AuraApiException catch (exception) {
      result = ApiHealth.failure(
        checkedAt: startedAt,
        responseTime: stopwatch.elapsed,
        error: exception.message,
      );
      rethrow;
    } catch (exception) {
      final String message = Redaction.sanitise(exception.toString());
      result = ApiHealth.failure(
        checkedAt: startedAt,
        responseTime: stopwatch.elapsed,
        error: message,
      );
      throw AuraApiException('AURA health check failed: $message');
    } finally {
      stopwatch.stop();
      final ApiHealth health = result ??
          ApiHealth.failure(
            checkedAt: startedAt,
            responseTime: stopwatch.elapsed,
            error: 'Health check ended without a result.',
          );
      this.onHealth?.call(health);
      onHealth?.call(health);
    }
  }

  Future<Map<String, dynamic>> getJson(String path) async {
    final DateTime startedAt = DateTime.now();
    final Stopwatch stopwatch = Stopwatch()..start();
    int? statusCode;
    String? error;
    final HttpClient client = HttpClient();
    try {
      final Uri uri = Uri.parse('$baseUrl$path');
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(timeout);
      if (path == '/api/system' && authToken != null && authToken!.isNotEmpty) {
        request.headers.add('authorization', 'Bearer $authToken');
      }
      final HttpClientResponse response =
          await request.close().timeout(timeout);
      statusCode = response.statusCode;
      final String body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw AuraApiException(
          'AURA API returned HTTP ${response.statusCode}.',
        );
      }
      final Object? decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const AuraApiException(
          'AURA API returned an unexpected response.',
        );
      }
      return decoded;
    } on AuraApiException catch (exception) {
      error = exception.message;
      rethrow;
    } on SocketException catch (exception) {
      error = exception.message;
      throw AuraApiException(
        'Cannot reach the AURA API at $baseUrl. '
        'Use Restart service in AURA Hub if it did not start automatically.',
      );
    } on TimeoutException {
      error = 'Timed out after ${timeout.inSeconds}s';
      throw AuraApiException(
        'The AURA API at $baseUrl did not respond in time.',
      );
    } on FormatException {
      error = 'Invalid JSON response';
      throw const AuraApiException('The AURA API returned invalid JSON.');
    } finally {
      stopwatch.stop();
      onRequest?.call(
        ApiRequestRecord(
          path: path,
          startedAt: startedAt,
          duration: stopwatch.elapsed,
          statusCode: statusCode,
          error: error,
        ),
      );
      client.close();
    }
  }
}
