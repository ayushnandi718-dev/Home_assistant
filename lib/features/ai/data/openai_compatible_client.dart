import 'dart:async';
import 'dart:convert';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/ai/data/ai_error_classifier.dart';
import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/openai_sse_parser.dart';
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

/// OpenAI-compatible chat-completions adapter (Groq-compatible).
///
/// Provider-independent from the UI's perspective: all configuration comes
/// from [AiProviderConfig], all transient secrets from [AiRequestContext], and
/// all network I/O from an injectable [AiHttpTransport]. No key or model id is
/// hardcoded here. [diagnostics] receives only redacted lifecycle metadata.
class OpenAiCompatibleAiClient implements AiProviderAdapter {
  const OpenAiCompatibleAiClient({
    required this.transport,
    this.diagnostics = const NoAiDiagnostics(),
  }) : _transport = transport;

  final AiHttpTransport transport;
  final AiHttpTransport _transport;
  final AiDiagnostics diagnostics;

  /// Recent messages sent with each request. Bounded to limit token cost.
  static const int maxContextMessages = AuraRuntimeConfig.maxAiContextMessages;

  static const int _maxModels = 200;
  static const int _maxModelFieldLength = 200;
  static const int _maxContextWindow = 100000000;

  /// OpenAI-compatible endpoints use this adapter. Loopback Ollama-style
  /// servers are temporarily mapped here until the native adapter lands.
  @override
  Set<AiProviderKind> get supportedKinds => const <AiProviderKind>{
        AiProviderKind.openAiCompatible,
        AiProviderKind.localOllama,
      };

  @override
  AiProviderCapabilities get capabilities => const AiProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        connectionTest: true,
      );

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.auto,
    AiRequestContext? context,
  }) async* {
    _validateForChat(config, context);

    final AiCancelToken? cancelToken = context?.cancelToken;
    if (cancelToken?.isCancelled ?? false) {
      throw const AiException(
          AiFailureKind.cancelled, 'Generation was cancelled.');
    }

    final String? apiKey = context?.apiKey?.trim();
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'text/event-stream',
      if (apiKey != null && apiKey.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
    };

    // Tools are an architecture extension point only. v1 never serialises or
    // executes tool calls, regardless of what the model asks for.
    final Map<String, Object?> body = <String, Object?>{
      'model': config.model.trim(),
      'stream': true,
      'messages': _buildPromptMessages(
        messages,
        language,
        context?.assembledContext,
      ),
    };

    final AiHttpRequest request = AiHttpRequest(
      method: AiHttpMethod.post,
      uri: _endpoint(config, 'chat/completions'),
      headers: headers,
      body: jsonEncode(body),
      timeout: context?.timeout ?? const Duration(seconds: 45),
    );
    final Stopwatch elapsed = Stopwatch()..start();
    int tokensReceived = 0;
    _record(
      providerId: config.id,
      request: request,
      stage: AiRequestStage.prepare,
      outcome: AiDiagnosticOutcome.started,
    );

    final AiHttpResponse response;
    try {
      response = await _transport.send(request, cancelToken: cancelToken);
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

    if (response.statusCode >= 400) {
      await _discard(response.body);
      final AiException failure = aiHttpException(response.statusCode);
      _record(
        providerId: config.id,
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

    try {
      await for (final String delta in parseOpenAiSse(response.body)) {
        if (cancelToken?.isCancelled ?? false) break;
        tokensReceived++;
        yield delta;
      }
      if (cancelToken?.isCancelled ?? false) {
        _record(
          providerId: config.id,
          request: request,
          stage: AiRequestStage.stream,
          outcome: AiDiagnosticOutcome.cancelled,
          durationMs: elapsed.elapsedMilliseconds,
          tokensReceived: tokensReceived,
        );
        return;
      }
      _record(
        providerId: config.id,
        request: request,
        stage: AiRequestStage.complete,
        outcome: AiDiagnosticOutcome.succeeded,
        durationMs: elapsed.elapsedMilliseconds,
        tokensReceived: tokensReceived,
      );
    } on AiException catch (error) {
      if (cancelToken?.isCancelled ?? false) {
        _record(
          providerId: config.id,
          request: request,
          stage: AiRequestStage.stream,
          outcome: AiDiagnosticOutcome.cancelled,
          failureKind: error.kind,
          durationMs: elapsed.elapsedMilliseconds,
          tokensReceived: tokensReceived,
        );
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
      if (cancelToken?.isCancelled ?? false) {
        _record(
          providerId: config.id,
          request: request,
          stage: AiRequestStage.stream,
          outcome: AiDiagnosticOutcome.cancelled,
          durationMs: elapsed.elapsedMilliseconds,
          tokensReceived: tokensReceived,
        );
        return;
      }
      final AiException failure = classifyAiTransportError(
        error,
        stage: AiRequestStage.stream,
        durationMs: elapsed.elapsedMilliseconds,
        fallbackMessage: 'The provider stream ended unexpectedly.',
      );
      _recordFailure(
        config: config,
        request: request,
        error: failure,
        tokensReceived: tokensReceived,
      );
      throw failure;
    }
  }

  /// Performs a real authenticated `/models` request. No prompt is sent.
  ///
  /// Success means metadata access worked. It deliberately does NOT claim that
  /// `/chat/completions` or the configured model will succeed.
  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    final _ModelsFetch fetched =
        await _fetchModels(config: config, context: context);
    final Object? decoded = fetched.decoded;
    if (decoded is! Map<String, dynamic> || decoded['data'] is! List<dynamic>) {
      final AiException failure = const AiException(
        AiFailureKind.malformedResponse,
        'The provider returned an unexpected response.',
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
      providerId: config.id,
      request: fetched.request,
      stage: AiRequestStage.complete,
      outcome: AiDiagnosticOutcome.succeeded,
      durationMs: fetched.elapsedMs,
      tokensReceived: 0,
    );
  }

  /// Discovers models through the same metadata endpoint used by connection
  /// tests. Raw provider payloads are reduced to bounded [AiModelInfo] values.
  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    final _ModelsFetch fetched =
        await _fetchModels(config: config, context: context);
    final List<AiModelInfo> models;
    try {
      models = _parseModels(fetched.decoded);
    } on FormatException {
      final AiException failure = const AiException(
        AiFailureKind.malformedResponse,
        'The provider returned an unreadable model list.',
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
      providerId: config.id,
      request: fetched.request,
      stage: AiRequestStage.complete,
      outcome: AiDiagnosticOutcome.succeeded,
      durationMs: fetched.elapsedMs,
      tokensReceived: 0,
    );
    return models;
  }

  Future<_ModelsFetch> _fetchModels({
    required AiProviderConfig config,
    required AiRequestContext? context,
  }) async {
    _validateForChat(config, context);
    final AiCancelToken? cancelToken = context?.cancelToken;
    if (cancelToken?.isCancelled ?? false) {
      throw const AiException(
        AiFailureKind.cancelled,
        'Generation was cancelled.',
      );
    }

    final String? apiKey = context?.apiKey?.trim();
    final AiHttpRequest request = AiHttpRequest(
      method: AiHttpMethod.get,
      uri: _endpoint(config, 'models'),
      headers: <String, String>{
        'Accept': 'application/json',
        if (apiKey != null && apiKey.isNotEmpty)
          'Authorization': 'Bearer $apiKey',
      },
      timeout: context?.timeout ?? const Duration(seconds: 20),
    );
    final Stopwatch elapsed = Stopwatch()..start();
    _record(
      providerId: config.id,
      request: request,
      stage: AiRequestStage.prepare,
      outcome: AiDiagnosticOutcome.started,
    );

    final AiHttpResponse response;
    try {
      response = await _transport.send(request, cancelToken: cancelToken);
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

    if (response.statusCode >= 400) {
      await _discard(response.body);
      final AiException failure = aiHttpException(response.statusCode);
      _record(
        providerId: config.id,
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
        'The provider returned an unreadable response.',
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
    return _ModelsFetch(
      request: request,
      decoded: decoded,
      elapsedMs: elapsed.elapsedMilliseconds,
    );
  }

  static List<AiModelInfo> _parseModels(Object? decoded) {
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Model list is not an object.');
    }
    final Object? raw = decoded['data'];
    if (raw is! List<dynamic> || raw.length > _maxModels) {
      throw const FormatException('Invalid model list.');
    }
    final List<AiModelInfo> result = <AiModelInfo>[];
    final Set<String> seenIds = <String>{};
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) {
        throw const FormatException('Invalid model entry.');
      }
      final Object? idValue = item['id'];
      if (idValue is! String) {
        throw const FormatException('Invalid model id.');
      }
      final String id = idValue.trim();
      if (id.isEmpty || id.length > _maxModelFieldLength || !seenIds.add(id)) {
        throw const FormatException('Invalid model id.');
      }
      result.add(
        AiModelInfo(
          id: id,
          label: _modelField(item['name'], fallback: id),
          contextWindow: _modelContextWindow(item['context_window']),
          ownedBy: _optionalModelField(item['owned_by']),
        ),
      );
    }
    return List<AiModelInfo>.unmodifiable(result);
  }

  static String _modelField(Object? value, {required String fallback}) {
    if (value is! String) return fallback;
    final String text = value.trim();
    if (text.isEmpty || text.length > _maxModelFieldLength) return fallback;
    return text;
  }

  static String? _optionalModelField(Object? value) {
    if (value is! String) return null;
    final String text = value.trim();
    if (text.isEmpty || text.length > _maxModelFieldLength) return null;
    return text;
  }

  static int? _modelContextWindow(Object? value) =>
      value is int && value > 0 && value <= _maxContextWindow ? value : null;

  void _recordFailure({
    required AiProviderConfig config,
    required AiHttpRequest request,
    required AiException error,
    required int tokensReceived,
  }) {
    _record(
      providerId: config.id,
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
    required String providerId,
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
        providerId: providerId,
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

  void _validateForChat(AiProviderConfig config, AiRequestContext? context) {
    final String? configError = config.validate();
    if (configError != null) {
      throw const AiException(
        AiFailureKind.configuration,
        'Provider configuration is incomplete.',
      );
    }
    if (config.kind == AiProviderKind.googleGemini) {
      throw const AiException(
        AiFailureKind.unsupportedProvider,
        'This provider kind is not supported by the OpenAI-compatible adapter.',
      );
    }
    final String? apiKey = context?.apiKey?.trim();
    if (!config.isLocal && (apiKey == null || apiKey.isEmpty)) {
      throw const AiException(
        AiFailureKind.missingCredentials,
        'An API key is required for this provider.',
      );
    }
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

    // Context-engine instructions are appended as system messages, never as
    // fake transcript entries. They are supplied only by the safe assembler.
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

  Uri _endpoint(AiProviderConfig config, String path) {
    final String base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    return Uri.parse('$base/$path');
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

class _ModelsFetch {
  const _ModelsFetch({
    required this.request,
    required this.decoded,
    required this.elapsedMs,
  });

  final AiHttpRequest request;
  final Object? decoded;
  final int elapsedMs;
}
