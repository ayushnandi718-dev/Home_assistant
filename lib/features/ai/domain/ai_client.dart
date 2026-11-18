import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';

/// Thrown when no real AI client adapter is available.
///
/// The UI can catch this to show an honest "not configured" state instead of
/// inventing a response. Real adapters use [AiException] for request failures.
class AiUnavailableException implements Exception {
  const AiUnavailableException([
    this.message =
        'AI is unavailable: no provider client is configured or implemented.',
  ]);

  final String message;

  @override
  String toString() => 'AiUnavailableException: $message';
}

/// Streaming client contract implemented by provider adapters.
///
/// The UI depends only on this boundary. [AiRequestContext] carries transient
/// credentials and cancellation without putting secrets into persisted config.
abstract class AiClient {
  const AiClient();

  /// Streams textual increments for the supplied transcript.
  ///
  /// [tools] is a future extension point only: v1 registers no executable
  /// tools and never acts on model-requested tool calls.
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.english,
    AiRequestContext? context,
  });

  /// Performs a real provider request and succeeds only if it authenticates.
  ///
  /// Adapters should use a cheap metadata endpoint where available, so a
  /// connection test does not transmit conversation content.
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  });
}

/// Honest fallback when no adapter is bound.
///
/// Calling either method throws immediately, so nothing can be mistaken for a
/// real model response or a successful connection.
class NoAiClient implements AiClient {
  const NoAiClient();

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.english,
    AiRequestContext? context,
  }) {
    throw const AiUnavailableException();
  }

  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) {
    throw const AiUnavailableException();
  }
}
