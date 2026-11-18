import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';

enum AiHttpMethod { get, post }

/// A provider request. Headers and body may contain secrets, so [toString] is
/// deliberately opaque and no transport implementation may log either field.
class AiHttpRequest {
  const AiHttpRequest({
    required this.method,
    required this.uri,
    this.headers = const <String, String>{},
    this.body,
    required this.timeout,
  });

  final AiHttpMethod method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
  final Duration timeout;

  @override
  String toString() => 'AiHttpRequest(${method.name})';
}

class AiHttpResponse {
  const AiHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final Stream<String> body;
}

/// Injectable network boundary so tests can use mocked responses and never
/// contact a real provider.
abstract class AiHttpTransport {
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  });
}

/// `dart:io` transport for desktop builds.
///
/// Uses only the configured endpoint. It has no knowledge of profiles, prompts
/// or credentials beyond placing a transient Authorization header on the wire.
class DartIoAiHttpTransport implements AiHttpTransport {
  const DartIoAiHttpTransport();

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    final HttpClient client = HttpClient()..connectionTimeout = request.timeout;
    HttpClientRequest? httpRequest;
    void Function()? cancelListener;

    try {
      final Future<HttpClientRequest> opening = switch (request.method) {
        AiHttpMethod.get => client.getUrl(request.uri),
        AiHttpMethod.post => client.postUrl(request.uri),
      };
      httpRequest = await opening.timeout(request.timeout);
      for (final MapEntry<String, String> header in request.headers.entries) {
        httpRequest.headers.set(header.key, header.value);
      }
      if (request.body != null) {
        httpRequest.write(request.body);
      }

      cancelListener = () {
        try {
          httpRequest?.abort();
        } catch (_) {
          // Abort is best-effort; cancellation is still honoured while reading.
        }
      };
      cancelToken?.addListener(cancelListener);

      final HttpClientResponse response =
          await httpRequest.close().timeout(request.timeout);

      return AiHttpResponse(
        statusCode: response.statusCode,
        body: _drainAndClose(
          response.transform(utf8.decoder).timeout(request.timeout),
          client,
          cancelToken,
          cancelListener,
        ),
      );
    } on TimeoutException {
      _cleanup(client, cancelToken, cancelListener);
      throw const AiException(
        AiFailureKind.timeout,
        'The provider did not respond in time.',
      );
    } on SocketException {
      _cleanup(client, cancelToken, cancelListener);
      throw const AiException(
        AiFailureKind.providerUnavailable,
        'The provider could not be reached.',
      );
    } catch (_) {
      _cleanup(client, cancelToken, cancelListener);
      if (cancelToken?.isCancelled ?? false) {
        throw const AiException(
          AiFailureKind.cancelled,
          'Generation was cancelled.',
        );
      }
      throw const AiException(
        AiFailureKind.unknown,
        'The provider request could not be completed.',
      );
    }
  }

  /// Keeps the HTTP client alive until the response body is fully consumed or
  /// the consumer cancels, then releases the socket and cancellation listener.
  Stream<String> _drainAndClose(
    Stream<String> source,
    HttpClient client,
    AiCancelToken? cancelToken,
    void Function() cancelListener,
  ) async* {
    try {
      await for (final String chunk in source) {
        if (cancelToken?.isCancelled ?? false) break;
        yield chunk;
      }
    } on TimeoutException {
      throw const AiException(
        AiFailureKind.timeout,
        'The provider stopped responding while streaming.',
      );
    } finally {
      cancelToken?.removeListener(cancelListener);
      client.close();
    }
  }

  void _cleanup(
    HttpClient client,
    AiCancelToken? cancelToken,
    void Function()? cancelListener,
  ) {
    if (cancelListener != null) cancelToken?.removeListener(cancelListener);
    client.close();
  }
}
