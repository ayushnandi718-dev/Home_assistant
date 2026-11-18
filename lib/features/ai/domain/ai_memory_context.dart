import 'package:aura_hub/core/config/aura_runtime_config.dart';

/// A caller-supplied, already-authorised memory snapshot.
///
/// The context assembler never reads a memory repository. It receives only this
/// immutable projection, which keeps the assembler pure and makes profile and
/// consent checks testable at the controller boundary.
class AiMemoryContextItem {
  const AiMemoryContextItem({
    required this.id,
    required this.categoryLabel,
    required this.content,
    this.updatedAt,
  });

  final String id;
  final String categoryLabel;
  final String content;
  final DateTime? updatedAt;
}

/// Retrieval seam used by the AI chat controller.
abstract class AiMemorySource {
  const AiMemorySource();

  /// Returns zero items when retrieval is disabled or permission is missing.
  Future<List<AiMemoryContextItem>> retrieveRelevant({
    required String query,
    required DateTime now,
    int limit = AuraRuntimeConfig.maxMemoryContextItems,
  });

  Future<void> markAccessed(List<String> ids);
}

/// Honest no-op used when no memory source is configured.
class NoAiMemorySource extends AiMemorySource {
  const NoAiMemorySource();

  @override
  Future<List<AiMemoryContextItem>> retrieveRelevant({
    required String query,
    required DateTime now,
    int limit = AuraRuntimeConfig.maxMemoryContextItems,
  }) async =>
      const <AiMemoryContextItem>[];

  @override
  Future<void> markAccessed(List<String> ids) async {}
}
