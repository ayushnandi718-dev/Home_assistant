import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/ai/domain/ai_memory_context.dart';
import 'package:aura_hub/features/memory/data/memory_repository.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';

/// Bridges the profile-scoped memory repository to the AI context engine.
///
/// The repository owns all profile, approval and consent checks. This adapter
/// only projects approved records into the AI domain's immutable snapshot.
class MemoryAiSource extends AiMemorySource {
  const MemoryAiSource(this._repository);

  final MemoryRepository _repository;

  @override
  Future<List<AiMemoryContextItem>> retrieveRelevant({
    required String query,
    required DateTime now,
    int limit = AuraRuntimeConfig.maxMemoryContextItems,
  }) async {
    final List<MemoryRecord> records = await _repository.retrieve(
      query: query,
      now: now,
      limit: limit,
    );
    return List<AiMemoryContextItem>.unmodifiable(
      records.map(
        (MemoryRecord record) => AiMemoryContextItem(
          id: record.id,
          categoryLabel: record.category.label,
          content: record.content,
          updatedAt: record.updatedAt,
        ),
      ),
    );
  }

  @override
  Future<void> markAccessed(List<String> ids) => _repository.markAccessed(ids);
}
