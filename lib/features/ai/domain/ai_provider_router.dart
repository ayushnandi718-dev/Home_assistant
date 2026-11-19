import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_registry.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';

/// Routes the shared [AiClient] API to a provider-specific adapter.
///
/// Controllers keep depending only on [AiClient]. Model discovery is exposed
/// here for future provider-management UI without changing chat controllers.
class AiProviderRouter implements AiClient {
  const AiProviderRouter({required this.registry});

  final AiProviderRegistry registry;

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.auto,
    AiRequestContext? context,
  }) {
    final AiProviderAdapter adapter = registry.adapterFor(config);
    return adapter.streamCompletion(
      config: config,
      messages: messages,
      tools: tools,
      language: language,
      context: context,
    );
  }

  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    await registry.adapterFor(config).testConnection(
          config: config,
          context: context,
        );
  }

  /// Returns bounded model metadata from the selected provider's adapter.
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    return registry.adapterFor(config).listModels(
          config: config,
          context: context,
        );
  }

  List<AiProviderDescriptor> get descriptors => registry.descriptors;
}
