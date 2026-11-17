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

/// Minimal JSON client for the local AURA telemetry service.
class AuraApiClient {
  AuraApiClient({
    String? baseUrl,
    this.timeout = const Duration(seconds: 5),
  }) : baseUrl = baseUrl ??
            const String.fromEnvironment(
              'AURA_API_BASE_URL',
              defaultValue: 'http://127.0.0.1:8765',
            );

  final String baseUrl;
  final Duration timeout;

  /// Base URL shown in the UI so it is always clear where data comes from.
  String get displayUrl => baseUrl.replaceFirst(RegExp(r'^https?://'), '');

  Future<Map<String, dynamic>> getJson(String path) async {
    final Uri uri = Uri.parse('$baseUrl$path');
    final HttpClient client = HttpClient();
    try {
      final HttpClientRequest request =
          await client.getUrl(uri).timeout(timeout);
      final HttpClientResponse response =
          await request.close().timeout(timeout);
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
    } on SocketException {
      throw AuraApiException(
        'Cannot reach the AURA API at $baseUrl. '
        'Start it with scripts\\start_aura_api.ps1.',
      );
    } on TimeoutException {
      throw AuraApiException(
        'The AURA API at $baseUrl did not respond in time.',
      );
    } on FormatException {
      throw const AuraApiException('The AURA API returned invalid JSON.');
    } finally {
      client.close();
    }
  }
}
