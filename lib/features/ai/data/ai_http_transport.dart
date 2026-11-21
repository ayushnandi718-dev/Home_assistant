import 'dart:async';
import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/features/ai/data/ai_error_classifier.dart';
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
/// All raw transport exceptions are classified here so the UI never receives
/// an opaque "request could not be completed" error.
class DartIoAiHttpTransport implements AiHttpTransport {
  const DartIoAiHttpTransport();

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    final HttpClient client = HttpClient()..connectionTimeout = request.timeout;
    final Stopwatch elapsed = Stopwatch()..start();
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
        // HttpClientRequest.encoding defaults to iso-8859-1, so write() throws
        // an ArgumentError for any non-Latin prompt text (e.g. Hindi/Bengali
        // system instructions). Encode explicitly as UTF-8 bytes instead.
        httpRequest.add(utf8.encode(request.body!));
      }

      cancelListener = () {
        try {
          httpRequest?.abort();
        } catch (_) {
          // Abort is best-effort; cancellation is still honoured while reading.
        }
        // Close the client immediately as well. Abort alone can leave the body
        // stream suspended on a stubborn peer, which would keep the socket and
        // the async generator alive even after the consumer has stopped.
        client.close();
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
          elapsed,
        ),
      );
    } on AiException {
      _cleanup(client, cancelToken, cancelListener);
      rethrow;
    } on Object catch (error) {
      _cleanup(client, cancelToken, cancelListener);
      throw classifyAiTransportError(
        error,
        stage: AiRequestStage.connect,
        durationMs: elapsed.elapsedMilliseconds,
        cancelled: cancelToken?.isCancelled ?? false,
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
    Stopwatch elapsed,
  ) async* {
    try {
      await for (final String chunk in source) {
        if (cancelToken?.isCancelled ?? false) break;
        yield chunk;
      }
    } on AiException {
      rethrow;
    } on Object catch (error) {
      // Cancellation is a normal stop, not a stream failure. Throwing here
      // produces an unhandled error when the consumer has already cancelled.
      if (cancelToken?.isCancelled ?? false) return;
      throw classifyAiTransportError(
        error,
        stage: AiRequestStage.stream,
        durationMs: elapsed.elapsedMilliseconds,
        fallbackMessage: 'The provider stream ended unexpectedly.',
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
