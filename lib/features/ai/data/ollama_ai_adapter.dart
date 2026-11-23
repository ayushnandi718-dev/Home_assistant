import 'dart:async';
import 'dart:convert';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/ai/data/ai_error_classifier.dart';
import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/domain/ai_context.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_diagnostics.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_prompt_policy.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';
import 'package:aura_hub/features/ai/domain/loopback_host.dart';

/// Native Ollama adapter using Ollama's own HTTP API.
///
/// This deliberately does not reuse the OpenAI-compatible wire format. Only
/// numeric loopback IP addresses are accepted in this build; hostnames such as
/// `localhost` are rejected so DNS cannot redirect a saved configuration to a
/// remote host. Ollama needs no credential: any transient key in
/// [AiRequestContext] is ignored, never stored, and never placed on the wire.
class OllamaAiAdapter implements AiProviderAdapter {
  const OllamaAiAdapter({
    required this.transport,
    this.diagnostics = const NoAiDiagnostics(),
  });

  static const String defaultBaseUrl = 'http://127.0.0.1:11434';
  static const int maxContextMessages = AuraRuntimeConfig.maxAiContextMessages;

  static const int _maxModels = 200;
  static const int _maxFieldLength = 200;
  static const int _maxSizeBytes = 1000000000000;
  static const Duration _availabilityTimeout = Duration(seconds: 5);
  static const Duration _metadataTimeout = Duration(seconds: 20);
  static const Duration _chatTimeout = Duration(seconds: 45);

  final AiHttpTransport transport;
  final AiDiagnostics diagnostics;

  @override
  Set<AiProviderKind> get supportedKinds => const <AiProviderKind>{
        AiProviderKind.localOllama,
      };

  @override
  AiProviderCapabilities get capabilities => const AiProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        connectionTest: true,
      );

  /// Non-secret default configuration for the native loopback endpoint.
  static AiProviderConfig defaultConfig({
    String id = 'ollama',
    String label = 'Local Ollama',
    String model = '',
    bool enabled = false,
    AiLanguage language = AiLanguage.auto,
  }) =>
      AiProviderConfig(
        id: id,
        label: label,
        kind: AiProviderKind.localOllama,
        baseUrl: defaultBaseUrl,
        model: model,
        enabled: enabled,
        language: language,
      );

  /// Graceful availability probe for UI status cards.
  ///
  /// A failure is reported as `false`; it never throws raw transport errors.
  Future<bool> isAvailable({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    try {
      final _OllamaFetch fetched = await _getJson(
        config: config,
        path: 'api/version',
        timeout: context?.timeout ?? _availabilityTimeout,
        context: context,
      );
      _parseVersion(fetched.decoded);
      _record(
        config: config,
        request: fetched.request,
        stage: AiRequestStage.complete,
        outcome: AiDiagnosticOutcome.succeeded,
        durationMs: fetched.elapsedMs,
        tokensReceived: 0,
      );
      return true;
    } on AiException catch (error) {
      _recordFailure(
        config: config,
        request: null,
        error: error,
        tokensReceived: 0,
      );
      return false;
    } on FormatException {
      return false;
    }
  }

  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    await listModels(config: config, context: context);
  }

  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    final _OllamaFetch fetched = await _getJson(
      config: config,
      path: 'api/tags',
      timeout: context?.timeout ?? _metadataTimeout,
      context: context,
    );
    final List<AiModelInfo> models;
    try {
      models = _parseModels(fetched.decoded);
    } on FormatException {
      final AiException failure = const AiException(
        AiFailureKind.malformedResponse,
        'The local model server returned an unreadable model list.',
        stage: AiRequestStage.parse,
      );
      _recordFailure(
        config: config,
        request: fetched.request,
        error: failure,
        tokensReceived: 0,
      );
      throw failure;
    }
    _record(
      config: config,
      request: fetched.request,
      stage: AiRequestStage.complete,
      outcome: AiDiagnosticOutcome.succeeded,
      durationMs: fetched.elapsedMs,
      tokensReceived: 0,
    );
    return models;
  }

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.auto,
    AiRequestContext? context,
  }) async* {
    _validateOllamaConfig(config, requireModel: true);
    final AiCancelToken? cancelToken = context?.cancelToken;
    if (cancelToken?.isCancelled ?? false) {
      throw const AiException(
        AiFailureKind.cancelled,
        'Generation was cancelled.',
      );
    }

    // Tools remain declaration-only. No tool payload is sent to any provider.
    final Map<String, Object?> body = <String, Object?>{
      'model': config.model.trim(),
      'messages': _buildPromptMessages(
        messages,
        language,
        context?.assembledContext,
      ),
      'stream': true,
    };
    final AiHttpRequest request = AiHttpRequest(
      method: AiHttpMethod.post,
      uri: _endpoint(config, 'api/chat'),
      headers: <String, String>{
        'Content-Type': 'application/json; charset=utf-8',
        'Accept': 'application/x-ndjson',
      },
      body: jsonEncode(body),
      timeout: context?.timeout ?? _chatTimeout,
    );

    final AiHttpResponse response = await _send(
      config: config,
      request: request,
      context: context,
    );
    if (response.statusCode >= 400) {
      await _discard(response.body);
      final AiException failure = aiHttpException(response.statusCode);
      _record(
        config: config,
        request: request,
        stage: AiRequestStage.response,
        outcome: AiDiagnosticOutcome.failed,
        statusCode: response.statusCode,
        failureKind: failure.kind,
        tokensReceived: 0,
      );
      throw failure;
    }

    final Stopwatch elapsed = Stopwatch()..start();
    int tokensReceived = 0;
    bool sawDone = false;
    String pending = '';
    bool cancelled = cancelToken?.isCancelled ?? false;

    // Bridge the transport through a local controller so cancellation closes
    // our consumer immediately instead of waiting for the server to emit a
    // further chunk. The transport subscription is cancelled as well, which
    // releases its HTTP client and socket.
    final StreamController<String> chunks = StreamController<String>();
    StreamSubscription<String>? bodySubscription;
    Future<void>? bodyCancelFuture;

    void closeChunks() {
      if (!chunks.isClosed) unawaited(chunks.close());
    }

    void releaseBody() {
      if (bodyCancelFuture != null) return;
      final StreamSubscription<String>? subscription = bodySubscription;
      if (subscription == null) return;
      bodyCancelFuture = subscription.cancel();
    }

    void handleCancel() {
      cancelled = true;
      closeChunks();
      releaseBody();
    }

    final void Function() cancelListener = handleCancel;
    cancelToken?.addListener(cancelListener);

    bodySubscription = response.body.listen(
      (String chunk) {
        if (cancelled || chunks.isClosed) return;
        chunks.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!chunks.isClosed) chunks.addError(error, stackTrace);
      },
      onDone: closeChunks,
      cancelOnError: true,
    );
    if (cancelled) releaseBody();

    void recordCancelled() {
      _record(
        config: config,
        request: request,
        stage: AiRequestStage.stream,
        outcome: AiDiagnosticOutcome.cancelled,
        durationMs: elapsed.elapsedMilliseconds,
        tokensReceived: tokensReceived,
      );
    }

    try {
      streamLoop:
      await for (final String chunk in chunks.stream) {
        if (cancelled || (cancelToken?.isCancelled ?? false)) {
          cancelled = true;
          break;
        }
        pending += chunk;
        while (true) {
          final int newline = pending.indexOf('\n');
          if (newline < 0) break;
          final String line = pending.substring(0, newline);
          pending = pending.substring(newline + 1);
          final _OllamaChunk? parsed = _parseStreamLine(line);
          if (parsed == null) continue;
          if (parsed.hasProviderError) {
            throw const AiException(
              AiFailureKind.serverError,
              'The local model server reported an error.',
              stage: AiRequestStage.stream,
            );
          }
          if (parsed.content.isNotEmpty) {
            tokensReceived++;
            yield parsed.content;
          }
          if (parsed.done) {
            // `done: true` is terminal. Anything already buffered after it is
            // discarded and no further delta can be emitted.
            sawDone = true;
            break streamLoop;
          }
        }
      }

      if (cancelled || (cancelToken?.isCancelled ?? false)) {
        recordCancelled();
        return;
      }
      if (!sawDone && pending.trim().isNotEmpty) {
        final _OllamaChunk? parsed = _parseStreamLine(pending);
        if (parsed != null) {
          if (parsed.hasProviderError) {
            throw const AiException(
              AiFailureKind.serverError,
              'The local model server reported an error.',
              stage: AiRequestStage.stream,
            );
          }
          if (parsed.content.isNotEmpty) {
            tokensReceived++;
            yield parsed.content;
          }
          if (parsed.done) sawDone = true;
        }
      }
      if (!sawDone) {
        throw const AiException(
          AiFailureKind.streamInterrupted,
          'The local model server ended the response before it was complete.',
          stage: AiRequestStage.stream,
        );
      }
      _record(
        config: config,
        request: request,
        stage: AiRequestStage.complete,
        outcome: AiDiagnosticOutcome.succeeded,
        durationMs: elapsed.elapsedMilliseconds,
        tokensReceived: tokensReceived,
      );
    } on AiException catch (error) {
      if (cancelled || (cancelToken?.isCancelled ?? false)) {
        recordCancelled();
        return;
      }
      _recordFailure(
        config: config,
        request: request,
        error: error,
        tokensReceived: tokensReceived,
      );
      rethrow;
    } on Object catch (error) {
      if (cancelled || (cancelToken?.isCancelled ?? false)) {
        recordCancelled();
        return;
      }
      final AiException failure = classifyAiTransportError(
        error,
        stage: AiRequestStage.stream,
        durationMs: elapsed.elapsedMilliseconds,
        fallbackMessage: 'The local model stream ended unexpectedly.',
      );
      _recordFailure(
        config: config,
        request: request,
        error: failure,
        tokensReceived: tokensReceived,
      );
      throw failure;
    } finally {
      cancelToken?.removeListener(cancelListener);
      closeChunks();
      // The cancel future can remain pending while the transport closes a
      // stubborn peer, but issuing cancel is enough to stop delivery and begin
      // socket cleanup. Do not make the caller wait on that peer.
      if (bodyCancelFuture == null) {
        final StreamSubscription<String> subscription = bodySubscription;
        unawaited(subscription.cancel());
      }
    }
  }

  Future<_OllamaFetch> _getJson({
    required AiProviderConfig config,
    required String path,
    required Duration timeout,
    required AiRequestContext? context,
  }) async {
    _validateOllamaConfig(config, requireModel: false);
    final AiCancelToken? cancelToken = context?.cancelToken;
    if (cancelToken?.isCancelled ?? false) {
      throw const AiException(
        AiFailureKind.cancelled,
        'Generation was cancelled.',
      );
    }
    final AiHttpRequest request = AiHttpRequest(
      method: AiHttpMethod.get,
      uri: _endpoint(config, path),
      headers: <String, String>{'Accept': 'application/json'},
      timeout: timeout,
    );
    final Stopwatch elapsed = Stopwatch()..start();
    _record(
      config: config,
      request: request,
      stage: AiRequestStage.prepare,
      outcome: AiDiagnosticOutcome.started,
    );

    final AiHttpResponse response = await _send(
      config: config,
      request: request,
      context: context,
    );
    if (response.statusCode >= 400) {
      await _discard(response.body);
      final AiException failure = aiHttpException(response.statusCode);
      _record(
        config: config,
        request: request,
        stage: AiRequestStage.response,
        outcome: AiDiagnosticOutcome.failed,
        statusCode: response.statusCode,
        failureKind: failure.kind,
        durationMs: elapsed.elapsedMilliseconds,
        tokensReceived: 0,
      );
      throw failure;
    }

    final String raw;
    try {
      raw = await response.body.join();
    } on AiException catch (error) {
      _recordFailure(
        config: config,
        request: request,
        error: error,
        tokensReceived: 0,
      );
      rethrow;
    } on Object catch (error) {
      final AiException failure = classifyAiTransportError(
        error,
        stage: AiRequestStage.response,
        durationMs: elapsed.elapsedMilliseconds,
        cancelled: cancelToken?.isCancelled ?? false,
      );
      _recordFailure(
        config: config,
        request: request,
        error: failure,
        tokensReceived: 0,
      );
      throw failure;
    }
    if (cancelToken?.isCancelled ?? false) {
      final AiException failure = const AiException(
        AiFailureKind.cancelled,
        'Generation was cancelled.',
      );
      _recordFailure(
        config: config,
        request: request,
        error: failure,
        tokensReceived: 0,
      );
      throw failure;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      final AiException failure = const AiException(
        AiFailureKind.malformedResponse,
        'The local model server returned an unreadable response.',
        stage: AiRequestStage.parse,
      );
      _recordFailure(
        config: config,
        request: request,
        error: failure,
        tokensReceived: 0,
      );
      throw failure;
    }
    return _OllamaFetch(
      request: request,
      decoded: decoded,
      elapsedMs: elapsed.elapsedMilliseconds,
    );
  }

  Future<AiHttpResponse> _send({
    required AiProviderConfig config,
    required AiHttpRequest request,
    required AiRequestContext? context,
  }) async {
    final AiCancelToken? cancelToken = context?.cancelToken;
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      return await transport.send(request, cancelToken: cancelToken);
    } on AiException catch (error) {
      _recordFailure(
        config: config,
        request: request,
        error: error,
        tokensReceived: 0,
      );
      rethrow;
    } on Object catch (error) {
      final AiException failure = classifyAiTransportError(
        error,
        stage: AiRequestStage.connect,
        durationMs: elapsed.elapsedMilliseconds,
        cancelled: cancelToken?.isCancelled ?? false,
      );
      _recordFailure(
        config: config,
        request: request,
        error: failure,
        tokensReceived: 0,
      );
      throw failure;
    }
  }

  static _OllamaChunk? _parseStreamLine(String raw) {
    final String line = raw.trim();
    if (line.isEmpty) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(line);
    } on FormatException {
      throw const AiException(
        AiFailureKind.malformedResponse,
        'The local model server returned an unreadable stream entry.',
        stage: AiRequestStage.parse,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const AiException(
        AiFailureKind.malformedResponse,
        'The local model server returned an unreadable stream entry.',
        stage: AiRequestStage.parse,
      );
    }
    final Object? error = decoded['error'];
    if (error != null) {
      if (error is! String || error.trim().isEmpty) {
        throw const AiException(
          AiFailureKind.malformedResponse,
          'The local model server returned an unreadable stream entry.',
          stage: AiRequestStage.parse,
        );
      }
      return const _OllamaChunk(hasProviderError: true);
    }
    final Object? done = decoded['done'];
    if (done != null && done is! bool) {
      throw const AiException(
        AiFailureKind.malformedResponse,
        'The local model server returned an unreadable stream entry.',
        stage: AiRequestStage.parse,
      );
    }
    if (decoded['done_reason'] == 'error') {
      return const _OllamaChunk(hasProviderError: true);
    }
    String content = '';
    final Object? message = decoded['message'];
    if (message != null) {
      if (message is! Map<String, dynamic>) {
        throw const AiException(
          AiFailureKind.malformedResponse,
          'The local model server returned an unreadable stream entry.',
          stage: AiRequestStage.parse,
        );
      }
      final Object? value = message['content'];
      if (value != null) {
        if (value is! String) {
          throw const AiException(
            AiFailureKind.malformedResponse,
            'The local model server returned an unreadable stream entry.',
            stage: AiRequestStage.parse,
          );
        }
        content = value;
      }
    }
    return _OllamaChunk(content: content, done: done == true);
  }

  static List<AiModelInfo> _parseModels(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model list is not an object.');
    }
    final Object? raw = decoded['models'];
    if (raw is! List<dynamic> || raw.length > _maxModels) {
      throw const FormatException('Invalid model list.');
    }
    final List<AiModelInfo> result = <AiModelInfo>[];
    final Set<String> seenIds = <String>{};
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid model entry.');
      }
      final String name = _requiredField(item['name']);
      final Object? modelValue = item['model'];
      final String identifier =
          modelValue == null ? name : _requiredField(modelValue);
      if (!seenIds.add(identifier)) {
        throw const FormatException('Duplicate model identifier.');
      }
      result.add(
        AiModelInfo(
          id: identifier,
          label: name,
          identifier: identifier,
          sizeBytes: _optionalSize(item['size']),
          modifiedAt: _optionalTimestamp(item['modified_at']),
          digest: _optionalField(item['digest']),
        ),
      );
    }
    return List<AiModelInfo>.unmodifiable(result);
  }

  static String _requiredField(Object? value) {
    if (value is! String) throw const FormatException('Invalid model field.');
    final String text = value.trim();
    if (text.isEmpty || text.length > _maxFieldLength) {
      throw const FormatException('Invalid model field.');
    }
    return text;
  }

  static String? _optionalField(Object? value) {
    if (value == null) return null;
    return _requiredField(value);
  }

  static int? _optionalSize(Object? value) {
    if (value == null) return null;
    if (value is! int || value < 0 || value > _maxSizeBytes) {
      throw const FormatException('Invalid model size.');
    }
    return value;
  }

  static DateTime? _optionalTimestamp(Object? value) {
    if (value == null) return null;
    if (value is! String) {
      throw const FormatException('Invalid model timestamp.');
    }
    final DateTime? parsed = DateTime.tryParse(value.trim());
    if (parsed == null) {
      throw const FormatException('Invalid model timestamp.');
    }
    return parsed;
  }

  static String _parseVersion(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid version response.');
    }
    return _requiredField(decoded['version']);
  }

  static void _validateOllamaConfig(AiProviderConfig config,
      {required bool requireModel}) {
    if (config.kind != AiProviderKind.localOllama) {
      throw const AiException(
        AiFailureKind.unsupportedProvider,
        'This provider kind is not supported by the native Ollama adapter.',
      );
    }
    if (config.id.trim().isEmpty || config.label.trim().isEmpty) {
      throw const AiException(
        AiFailureKind.configuration,
        'Provider configuration is incomplete.',
      );
    }
    if (requireModel && config.model.trim().isEmpty) {
      throw const AiException(
        AiFailureKind.configuration,
        'Choose an installed model before starting a chat.',
      );
    }

    final Uri? uri = Uri.tryParse(config.baseUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      throw const AiException(
        AiFailureKind.configuration,
        'Ollama base URL must be an absolute URL.',
      );
    }
    final String scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      throw const AiException(
        AiFailureKind.configuration,
        'Ollama base URL must use http or https.',
      );
    }
    if (!LoopbackHost.isLiteralLoopback(uri.host)) {
      throw const AiException(
        AiFailureKind.configuration,
        'Ollama is limited to numeric loopback IP addresses in this build.',
      );
    }
    if (uri.hasQuery || uri.hasFragment || uri.userInfo.isNotEmpty) {
      throw const AiException(
        AiFailureKind.configuration,
        'Ollama base URL must not contain a query, fragment or user info.',
      );
    }
  }

  Uri _endpoint(AiProviderConfig config, String path) {
    final String base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/$path');
  }

  List<Map<String, String>> _buildPromptMessages(
    List<AiMessage> transcript,
    AiLanguage language,
    AiAssembledContext? assembledContext,
  ) {
    final List<Map<String, String>> result = <Map<String, String>>[
      <String, String>{
        'role': 'system',
        'content': AiPromptPolicy.systemInstruction(language),
      },
    ];
    if (assembledContext != null) {
      for (final String instruction in assembledContext.systemInstructions) {
        final String text = instruction.trim();
        if (text.isNotEmpty) {
          result.add(<String, String>{'role': 'system', 'content': text});
        }
      }
    }
    final List<AiMessage> history = transcript
        .where((AiMessage message) =>
            message.role != AiMessageRole.system &&
            message.content.trim().isNotEmpty)
        .toList(growable: false);
    final List<AiMessage> kept = history.length > maxContextMessages
        ? history.sublist(history.length - maxContextMessages)
        : history;
    for (final AiMessage message in kept) {
      result.add(<String, String>{
        'role': message.role.name,
        'content': message.content,
      });
    }
    return result;
  }

  void _recordFailure({
    required AiProviderConfig config,
    required AiHttpRequest? request,
    required AiException error,
    required int tokensReceived,
  }) {
    if (request == null) return;
    _record(
      config: config,
      request: request,
      stage: error.stage ?? AiRequestStage.connect,
      outcome: error.kind == AiFailureKind.cancelled
          ? AiDiagnosticOutcome.cancelled
          : AiDiagnosticOutcome.failed,
      statusCode: error.statusCode,
      failureKind: error.kind,
      exceptionType: error.exceptionType,
      durationMs: error.durationMs,
      tokensReceived: tokensReceived,
    );
  }

  void _record({
    required AiProviderConfig config,
    required AiHttpRequest request,
    required AiRequestStage stage,
    required AiDiagnosticOutcome outcome,
    int? statusCode,
    AiFailureKind? failureKind,
    String? exceptionType,
    int? durationMs,
    int? tokensReceived,
  }) {
    diagnostics.record(
      AiDiagnosticEvent(
        stage: stage,
        providerId: config.id,
        host: _safeHost(request.uri),
        method: request.method.name.toUpperCase(),
        outcome: outcome,
        statusCode: statusCode,
        failureKind: failureKind,
        exceptionType: exceptionType,
        durationMs: durationMs,
        tokensReceived: tokensReceived,
      ),
    );
  }

  String _safeHost(Uri uri) {
    final String host = uri.host.trim().toLowerCase();
    return host.isEmpty ? 'local' : host;
  }

  Future<void> _discard(Stream<String> body) async {
    try {
      await for (final String _ in body) {
        // Drain error bodies so the transport can release its HTTP client.
      }
    } on Object {
      // Error bodies are never shown and must not mask the status failure.
    }
  }
}

class _OllamaChunk {
  const _OllamaChunk({
    this.content = '',
    this.done = false,
    this.hasProviderError = false,
  });

  final String content;
  final bool done;
  final bool hasProviderError;
}

class _OllamaFetch {
  const _OllamaFetch({
    required this.request,
    required this.decoded,
    required this.elapsedMs,
  });

  final AiHttpRequest request;
  final Object? decoded;
  final int elapsedMs;
}
