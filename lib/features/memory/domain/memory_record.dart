import 'dart:math';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_status.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Immutable, profile-owned memory record.
///
/// The field list is an allowlist. There is deliberately no place for a PIN,
/// API key, token, password or arbitrary metadata blob, so those values cannot
/// be persisted by reusing this model.
class MemoryRecord {
  const MemoryRecord({
    required this.id,
    required this.profile,
    required this.content,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.tags = const <String>[],
    this.expiresAt,
    this.lastAccessedAt,
    this.sourceConversationId,
    this.sourceMessageId,
  });

  static const int schemaVersion = 1;

  /// Stable id without adding a UUID dependency.
  static String newId() {
    final DateTime now = DateTime.now();
    final int random = Random.secure().nextInt(1 << 30);
    return 'mem-${now.microsecondsSinceEpoch}-${random.toRadixString(36)}';
  }

  final String id;
  final AuraProfile profile;
  final String content;
  final MemoryCategory category;
  final MemoryStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<String> tags;
  final DateTime? expiresAt;
  final DateTime? lastAccessedAt;
  final String? sourceConversationId;
  final String? sourceMessageId;

  String get displayText {
    final String clean = content.trim();
    final int end = clean.indexOf('\n');
    return end < 0 ? clean : clean.substring(0, end);
  }

  bool isExpiredAt(DateTime now) =>
      expiresAt != null && !expiresAt!.isAfter(now);

  /// Complete gate for retrieval. Callers still apply profile and consent rules.
  bool isRetrievableAt(DateTime now) =>
      status == MemoryStatus.approved && !isExpiredAt(now);

  String? get validationError {
    if (id.trim().isEmpty || id.length > 120) return 'Invalid memory id.';
    final String clean = content.trim();
    if (clean.isEmpty) return 'Enter the information to remember.';
    if (clean.length > AuraRuntimeConfig.maxMemoryContentChars) {
      return 'Memory is too long. Shorten it and try again.';
    }
    if (tags.length > AuraRuntimeConfig.maxMemoryTags) {
      return 'Use fewer tags.';
    }
    for (final String tag in tags) {
      if (tag.trim().isEmpty ||
          tag.length > AuraRuntimeConfig.maxMemoryTagChars) {
        return 'Each tag must be short and non-empty.';
      }
    }
    return null;
  }

  MemoryRecord copyWith({
    String? content,
    MemoryCategory? category,
    MemoryStatus? status,
    List<String>? tags,
    DateTime? updatedAt,
    DateTime? expiresAt,
    DateTime? lastAccessedAt,
    String? sourceConversationId,
    String? sourceMessageId,
    bool clearExpiresAt = false,
    bool clearLastAccessedAt = false,
    bool clearSourceConversationId = false,
    bool clearSourceMessageId = false,
  }) {
    return MemoryRecord(
      id: id,
      profile: profile,
      content: content ?? this.content,
      category: category ?? this.category,
      status: status ?? this.status,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      tags: tags ?? List<String>.unmodifiable(this.tags),
      expiresAt: clearExpiresAt ? null : expiresAt ?? this.expiresAt,
      lastAccessedAt:
          clearLastAccessedAt ? null : lastAccessedAt ?? this.lastAccessedAt,
      sourceConversationId: clearSourceConversationId
          ? null
          : sourceConversationId ?? this.sourceConversationId,
      sourceMessageId:
          clearSourceMessageId ? null : sourceMessageId ?? this.sourceMessageId,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schemaVersion,
        'id': id,
        'profile': profile.storageScope,
        'content': content.trim(),
        'category': category.storageKey,
        'status': status.storageKey,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        if (tags.isNotEmpty) 'tags': List<String>.unmodifiable(tags),
        if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
        if (lastAccessedAt != null)
          'lastAccessedAt': lastAccessedAt!.toIso8601String(),
        if (sourceConversationId != null)
          'sourceConversationId': sourceConversationId!,
        if (sourceMessageId != null) 'sourceMessageId': sourceMessageId!,
      };

  /// Returns null for malformed, foreign-scope or future-schema records.
  static MemoryRecord? tryFromJson(Object? value,
      {required AuraProfile profile}) {
    if (value is! Map<String, dynamic>) return null;
    final Object? schema = value['schema'];
    if (schema is int && schema > schemaVersion) return null;
    if (value['profile'] != profile.storageScope) return null;

    final Object? id = value['id'];
    final Object? content = value['content'];
    final MemoryCategory? category =
        MemoryCategoryX.fromStorage(value['category']);
    final MemoryStatus? status = MemoryStatusX.fromStorage(value['status']);
    if (id is! String ||
        content is! String ||
        category == null ||
        status == null) {
      return null;
    }

    final DateTime createdAt = _date(value['createdAt']) ?? DateTime.now();
    final DateTime updatedAt = _date(value['updatedAt']) ?? createdAt;
    final MemoryRecord record = MemoryRecord(
      id: id,
      profile: profile,
      content: content,
      category: category,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
      tags: _stringList(value['tags']),
      expiresAt: _date(value['expiresAt']),
      lastAccessedAt: _date(value['lastAccessedAt']),
      sourceConversationId: _text(value['sourceConversationId']),
      sourceMessageId: _text(value['sourceMessageId']),
    );
    return record.validationError == null ? record : null;
  }

  static DateTime? _date(Object? value) =>
      value is String ? DateTime.tryParse(value) : null;

  static String? _text(Object? value) {
    if (value is! String) return null;
    final String clean = value.trim();
    return clean.isEmpty ? null : clean;
  }

  static List<String> _stringList(Object? value) {
    if (value is! List<dynamic>) return const <String>[];
    final List<String> result = <String>[];
    for (final Object? item in value) {
      final String? clean = _text(item);
      if (clean == null || clean.length > AuraRuntimeConfig.maxMemoryTagChars) {
        continue;
      }
      if (result.length >= AuraRuntimeConfig.maxMemoryTags) break;
      result.add(clean);
    }
    return List<String>.unmodifiable(result);
  }
}
