import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';

/// Deterministic, local relevance ranking.
///
/// No embeddings, network calls or background extraction. Candidates must
/// already be profile-scoped and approved; this service keeps only records with
/// actual query overlap, orders a bounded snapshot, and drops records that are
/// no longer retrievable. Recency is a tie-break, not a reason to send an
/// unrelated memory.
abstract final class MemoryRetrieval {
  static List<MemoryRecord> rank({
    required List<MemoryRecord> candidates,
    required String query,
    required DateTime now,
    int limit = 5,
  }) {
    final String phrase = query.trim().toLowerCase();
    if (limit <= 0 || phrase.isEmpty) return const <MemoryRecord>[];
    final Set<String> queryTokens = _tokens(query);
    final List<_ScoredMemory> scored = <_ScoredMemory>[];

    for (final MemoryRecord record in candidates) {
      if (!record.isRetrievableAt(now) || record.validationError != null) {
        continue;
      }
      final Set<String> contentTokens = _tokens(record.content);
      final Set<String> tagTokens = _tokens(record.tags.join(' '));
      final Set<String> categoryTokens = _tokens(record.category.label);

      int relevance = 0;
      for (final String token in queryTokens) {
        if (contentTokens.contains(token)) relevance += 3;
        if (tagTokens.contains(token)) relevance += 2;
        if (categoryTokens.contains(token)) relevance += 1;
      }
      if (record.content.toLowerCase().contains(phrase)) relevance += 4;
      if (relevance == 0) continue;

      final int ageDays = now.difference(record.updatedAt).inDays;
      final int recency =
          ageDays <= 0 ? 30 : (30 - (ageDays ~/ 30)).clamp(0, 30);

      scored.add(
        _ScoredMemory(
          record: record,
          score: relevance + recency,
          updatedAt: record.updatedAt,
        ),
      );
    }

    scored.sort((_ScoredMemory a, _ScoredMemory b) {
      final int byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final int byDate = b.updatedAt.compareTo(a.updatedAt);
      if (byDate != 0) return byDate;
      return a.record.id.compareTo(b.record.id);
    });

    return List<MemoryRecord>.unmodifiable(
      scored.take(limit).map((_ScoredMemory item) => item.record).toList(),
    );
  }

  static Set<String> _tokens(String text) =>
      RegExp(r'[\p{L}\p{N}]+', unicode: true)
          .allMatches(text.toLowerCase())
          .map((Match match) => match.group(0)!)
          .where((String token) => token.length > 1)
          .toSet();
}

class _ScoredMemory {
  const _ScoredMemory({
    required this.record,
    required this.score,
    required this.updatedAt,
  });

  final MemoryRecord record;
  final int score;
  final DateTime updatedAt;
}
