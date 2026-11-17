import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
        if (error != null) 'error': error,
        'succeeded': succeeded,
      };
}

typedef ApiRequestRecorder = void Function(ApiRequestRecord record);

/// Minimal JSON client for the local AURA telemetry service.
class AuraApiClient {
  AuraApiClient({
    String? baseUrl,
    this.timeout = const Duration(seconds: 5),
    this.onRequest,
  }) : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'AURA_API_BASE_URL',
              defaultValue: 'http://127.0.0.1:8765',
            );

  final String baseUrl;
  final Duration timeout;
  final ApiRequestRecorder? onRequest;

  /// Base URL shown in the UI so it is always clear where data comes from.
  String get displayUrl => baseUrl.replaceFirst(RegExp(r'^https?://'), '');

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
        'Start it with scripts\\start_aura_api.ps1.',
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
