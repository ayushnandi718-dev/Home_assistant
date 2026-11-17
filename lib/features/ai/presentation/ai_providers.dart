import 'dart:async';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest readiness of the AI foundation.
///
/// There is intentionally no 'connected' or 'ready' value: no client adapter
/// exists in this build, so an enabled config can never mean a usable model.
enum AiReadiness {
  /// No enabled provider config is stored.
  unconfigured,

  /// A config exists, but no provider client adapter is implemented.
  notImplemented,
}

/// Owns the stored provider configs and exposes the enabled subset.
class AiConfigController extends StateNotifier<List<AiProviderConfig>> {
  AiConfigController({AiConfigStore? store, AuraLogger? logger})
      : _store = store ?? AiConfigStore(),
        _logger = logger ?? AuraLogger(),
        super(const <AiProviderConfig>[]) {
    unawaited(load());
  }

  final AiConfigStore _store;
  final AuraLogger _logger;

  Future<void> load() async => state = await _store.load();

  /// Enabled configs only. Enabling a config does NOT connect to a provider.
  List<AiProviderConfig> get enabledProviders => state
      .where((AiProviderConfig config) => config.enabled)
      .toList(growable: false);

  Future<void> upsert(AiProviderConfig config) async {
    state = await _store.upsert(config);
    _logger.info('ai', 'Provider config saved: ${config.id}');
  }

  Future<void> clear() async {
    await _store.save(const <AiProviderConfig>[]);
    state = const <AiProviderConfig>[];
    _logger.info('ai', 'Provider configs cleared');
  }
}

/// Holds one bounded transcript per conversation id, in memory only.
class AiConversationController extends StateNotifier<AiConversation> {
  AiConversationController(String id) : super(AiConversation(id: id));

  /// Appends a caller-supplied message; no content is generated here.
  void append(AiMessage message) => state = state.append(message);

  void clear() => state = state.clear();
}

final Provider<AiConfigStore> aiConfigStoreProvider =
    Provider<AiConfigStore>((Ref ref) => AiConfigStore());

final StateNotifierProvider<AiConfigController, List<AiProviderConfig>>
    aiConfigsProvider =
    StateNotifierProvider<AiConfigController, List<AiProviderConfig>>(
  (Ref ref) => AiConfigController(
    store: ref.read(aiConfigStoreProvider),
    logger: ref.read(auraLoggerProvider.notifier),
  ),
);

final StateNotifierProviderFamily<AiConversationController, AiConversation,
        String> aiConversationsProvider =
    StateNotifierProvider.family<AiConversationController, AiConversation,
        String>((Ref ref, String id) {
  return AiConversationController(id);
});

/// Always the honest no-op client for now. No adapter is implemented.
final Provider<AiClient> aiClientProvider = Provider<AiClient>((Ref ref) {
  return const NoAiClient();
});

/// In-memory language preference for the informational language selector.
final StateProvider<AiLanguage> aiLanguageProvider =
    StateProvider<AiLanguage>((Ref ref) => AiLanguage.english);

/// Reports `unconfigured` with no enabled config, otherwise `notImplemented`.
final Provider<AiReadiness> aiReadinessProvider =
    Provider<AiReadiness>((Ref ref) {
  final List<AiProviderConfig> configs = ref.watch(aiConfigsProvider);
  if (configs.isEmpty) return AiReadiness.unconfigured;
  final AiConfigController controller = ref.read(aiConfigsProvider.notifier);
  return controller.enabledProviders.isEmpty
      ? AiReadiness.unconfigured
      : AiReadiness.notImplemented;
});
