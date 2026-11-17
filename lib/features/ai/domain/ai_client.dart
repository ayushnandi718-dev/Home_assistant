import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';

/// Thrown when no real AI client adapter is available.
///
/// The UI can catch this to show an honest "not configured / not implemented"
/// state instead of inventing a response.
class AiUnavailableException implements Exception {
  const AiUnavailableException([
    this.message =
        'AI is unavailable: no provider client is configured or implemented.',
  ]);

  final String message;

  @override
  String toString() => 'AiUnavailableException: $message';
}

/// Streaming client contract for a future AI provider adapter.
///
/// This is an interface only. Implementing it does NOT happen in this build,
/// and this file contains no HTTP, socket or other network code.
abstract class AiClient {
  const AiClient();

  /// Streams textual increments for the supplied transcript.
  ///
  /// [tools] and [language] are part of the contract for future adapters; no
  /// implementation in this build consumes them.
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.english,
  });
}

/// Honest default client for a build with no adapter.
///
/// Calling [streamCompletion] throws immediately, so nothing can be mistaken
/// for a real model response. This client never performs any network call.
class NoAiClient implements AiClient {
  const NoAiClient();

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.english,
  }) {
    throw const AiUnavailableException();
  }
}
