import 'dart:convert';

import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/openai_sse_parser.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_prompt_policy.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';

/// OpenAI-compatible chat-completions adapter (Groq-compatible).
///
/// Provider-independent from the UI's perspective: all configuration comes
/// from [AiProviderConfig], all transient secrets from [AiRequestContext], and
/// all network I/O from an injectable [AiHttpTransport]. No key or model id is
/// hardcoded here.
class OpenAiCompatibleAiClient implements AiClient {
  const OpenAiCompatibleAiClient({required this.transport})
      : _transport = transport;

  final AiHttpTransport transport;
  final AiHttpTransport _transport;

  /// Recent messages sent with each request. Bounded to limit token cost.
  static const int maxContextMessages = 20;

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.english,
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
      'Content-Type': 'application/json',
      'Accept': 'text/event-stream',
      if (apiKey != null && apiKey.isNotEmpty)
        'Authorization': 'Bearer $apiKey',
    };

    // Tools are an architecture extension point only. v1 never serialises or
    // executes tool calls, regardless of what the model asks for.
    final Map<String, Object?> body = <String, Object?>{
      'model': config.model.trim(),
      'stream': true,
      'messages': _buildPromptMessages(messages, language),
    };

    final AiHttpResponse response;
    try {
      response = await _transport.send(
        AiHttpRequest(
          method: AiHttpMethod.post,
          uri: _endpoint(config, 'chat/completions'),
          headers: headers,
          body: jsonEncode(body),
          timeout: context?.timeout ?? const Duration(seconds: 45),
        ),
        cancelToken: cancelToken,
      );
    } on AiException {
      rethrow;
    } catch (_) {
      throw const AiException(
        AiFailureKind.unknown,
        'The provider request could not be started.',
      );
    }

    if (response.statusCode >= 400) {
      await _discard(response.body);
      throw aiHttpException(response.statusCode);
    }

    try {
      await for (final String delta in parseOpenAiSse(response.body)) {
        if (cancelToken?.isCancelled ?? false) break;
        yield delta;
      }
    } on AiException {
      rethrow;
    } catch (_) {
      if (cancelToken?.isCancelled ?? false) {
        throw const AiException(
          AiFailureKind.cancelled,
          'Generation was cancelled.',
        );
      }
      throw const AiException(
        AiFailureKind.malformedResponse,
        'The provider stream ended unexpectedly.',
      );
    }
  }

  /// Performs a real authenticated `/models` request. No prompt is sent.
  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
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
        'An API key is required to test this provider.',
      );
    }

    final AiHttpResponse response;
    try {
      response = await _transport.send(
        AiHttpRequest(
          method: AiHttpMethod.get,
          uri: _endpoint(config, 'models'),
          headers: <String, String>{
            'Accept': 'application/json',
            if (apiKey != null && apiKey.isNotEmpty)
              'Authorization': 'Bearer $apiKey',
          },
          timeout: context?.timeout ?? const Duration(seconds: 20),
        ),
        cancelToken: context?.cancelToken,
      );
    } on AiException {
      rethrow;
    } catch (_) {
      if (context?.cancelToken?.isCancelled ?? false) {
        throw const AiException(
          AiFailureKind.cancelled,
          'Connection test was cancelled.',
        );
      }
      throw const AiException(
        AiFailureKind.providerUnavailable,
        'The provider could not be reached.',
      );
    }

    if (response.statusCode >= 400) {
      await _discard(response.body);
      throw aiHttpException(response.statusCode);
    }

    final String raw = await response.body.join();
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic> ||
          decoded['data'] is! List<dynamic>) {
        throw const AiException(
          AiFailureKind.malformedResponse,
          'The provider returned an unexpected response.',
        );
      }
    } on FormatException {
      throw const AiException(
        AiFailureKind.malformedResponse,
        'The provider returned an unreadable response.',
      );
    }
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
  ) {
    final List<Map<String, String>> result = <Map<String, String>>[
      <String, String>{
        'role': 'system',
        'content': AiPromptPolicy.systemInstruction(language),
      },
    ];
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
    await for (final String _ in body) {
      // Drain error bodies so the transport can release its HTTP client.
    }
  }
}
