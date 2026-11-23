import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/memory_settings_store.dart';
import 'package:aura_hub/features/memory/data/memory_store.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/memory/domain/memory_retrieval.dart';
import 'package:aura_hub/features/memory/domain/memory_safety.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/memory/domain/memory_status.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Outcome of a user-authorised memory mutation. Messages are fixed and never
/// include memory content or provider text.
enum MemoryWriteOutcome {
  success,
  accessDenied,
  notFound,
  invalid,
  sensitiveContent,
  disabled,
  storageFailed,

  /// Encrypted storage is unavailable, corrupt or undecryptable.
  ///
  /// The affected file is never replaced and memory access stays blocked.
  storageSecurityError,
}

class MemoryWriteResult {
  const MemoryWriteResult(this.outcome, [this.userMessage]);

  final MemoryWriteOutcome outcome;
  final String? userMessage;

  bool get isSuccess => outcome == MemoryWriteOutcome.success;

  static const MemoryWriteResult ok = MemoryWriteResult(
    MemoryWriteOutcome.success,
  );
}

/// Application boundary for every memory mutation and retrieval.
abstract class MemoryRepository {
  AuraProfile get profile;

  Future<List<MemoryRecord>> load();
  Future<MemorySettings> loadSettings();
  Future<MemoryWriteResult> saveSettings(MemorySettings settings);

  Future<MemoryWriteResult> createApproved({
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
  });

  Future<MemoryWriteResult> suggest({
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
  });

  Future<MemoryWriteResult> approve(String id);
  Future<MemoryWriteResult> reject(String id);

  Future<MemoryWriteResult> update({
    required String id,
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
  });

  Future<MemoryWriteResult> delete(String id);
  Future<MemoryWriteResult> clear();

  Future<List<MemoryRecord>> retrieve({
    required String query,
    required DateTime now,
    int limit = AuraRuntimeConfig.maxMemoryContextItems,
  });

  Future<void> markAccessed(List<String> ids);

  /// Clears in-memory state when the private session is locked or switched.
  void discardForLock();
}

/// Optional status surface for repositories backed by encrypted storage.
///
/// This is separate from [MemoryRepository] so simple test doubles and the
/// shared FAMILY repository do not need to model recovery state.
abstract interface class MemoryStorageStatusReader {
  String? get storageErrorMessage;
}

/// Local repository bound to exactly one profile at construction.
class LocalMemoryRepository
    implements MemoryRepository, MemoryStorageStatusReader {
  LocalMemoryRepository({
    required this.profile,
    required MemoryRecordStore store,
    required MemorySettingsStorage settingsStore,
    required ProfileAccessReader accessReader,
  })  : _store = store,
        _settingsStore = settingsStore,
        _accessReader = accessReader;

  @override
  final AuraProfile profile;

  final MemoryRecordStore _store;
  final MemorySettingsStorage _settingsStore;
  final ProfileAccessReader _accessReader;

  List<MemoryRecord> _records = const <MemoryRecord>[];
  MemorySettings _settings = MemorySettings.defaults;
  bool _loaded = false;
  String? _storageError;

  @override
  String? get storageErrorMessage => _storageError;

  static const MemoryWriteResult _accessDenied = MemoryWriteResult(
    MemoryWriteOutcome.accessDenied,
    'Unlock the AYUSH workspace before accessing its memories.',
  );

  ProfileOperationOwner? _beginOwner() {
    try {
      return ProfileOperationOwner(
        accessReader: _accessReader,
        profile: profile,
      );
    } on AuraProfileAccessDenied {
      return null;
    }
  }

  Future<MemoryWriteResult> _guard(ProfileOperationOwner owner) async {
    if (!owner.isCurrent) return _accessDenied;
    if (_storageError != null) {
      return MemoryWriteResult(
        MemoryWriteOutcome.storageSecurityError,
        _storageError,
      );
    }
    if (!_loaded) {
      bool writeAllowed() => owner.isCurrent;
      late final List<MemoryRecord> records;
      late final MemorySettings settings;
      try {
        records = await _store.load(isWriteAllowed: writeAllowed);
        if (!owner.isCurrent) return _accessDenied;
        settings = await _settingsStore.load(isWriteAllowed: writeAllowed);
      } on MemoryStorageException catch (error) {
        _records = const <MemoryRecord>[];
        _settings = MemorySettings.defaults;
        _storageError = error.userMessage;
        return MemoryWriteResult(
          MemoryWriteOutcome.storageSecurityError,
          error.userMessage,
        );
      }
      if (!owner.isCurrent) return _accessDenied;
      _records = records;
      _settings = settings;
      _loaded = true;
    }
    return MemoryWriteResult.ok;
  }

  Future<MemoryWriteResult> _commit(
    List<MemoryRecord> next,
    ProfileOperationOwner owner,
  ) async {
    bool writeAllowed() => owner.isCurrent;
    if (!owner.isCurrent) return _accessDenied;
    try {
      final bool saved = await _store.save(next, isWriteAllowed: writeAllowed);
      if (!owner.isCurrent) return _accessDenied;
      if (!saved) {
        return const MemoryWriteResult(
          MemoryWriteOutcome.storageFailed,
          'Memory could not be saved locally. Please try again.',
        );
      }
    } on MemoryStorageException catch (error) {
      _storageError = error.userMessage;
      return MemoryWriteResult(
        MemoryWriteOutcome.storageSecurityError,
        error.userMessage,
      );
    }
    _records = List<MemoryRecord>.unmodifiable(next);
    return MemoryWriteResult.ok;
  }

  @override
  Future<List<MemoryRecord>> load() async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return const <MemoryRecord>[];
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess || !owner.isCurrent) return const <MemoryRecord>[];
    return _records;
  }

  @override
  Future<MemorySettings> loadSettings() async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return MemorySettings.defaults;
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess || !owner.isCurrent) return MemorySettings.defaults;
    return _settings;
  }

  @override
  Future<MemoryWriteResult> saveSettings(MemorySettings settings) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return _accessDenied;
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess) return guard;
    if (!owner.isCurrent) return _accessDenied;
    bool writeAllowed() => owner.isCurrent;
    try {
      final bool saved = await _settingsStore.save(
        settings,
        isWriteAllowed: writeAllowed,
      );
      if (!owner.isCurrent) return _accessDenied;
      if (!saved) {
        return const MemoryWriteResult(
          MemoryWriteOutcome.storageFailed,
          'Memory settings could not be saved. Please try again.',
        );
      }
    } on MemoryStorageException catch (error) {
      _storageError = error.userMessage;
      return MemoryWriteResult(
        MemoryWriteOutcome.storageSecurityError,
        error.userMessage,
      );
    }
    _settings = settings;
    return MemoryWriteResult.ok;
  }

  @override
  Future<MemoryWriteResult> createApproved({
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
  }) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return _accessDenied;
    return _create(
      content: content,
      category: category,
      status: MemoryStatus.approved,
      tags: tags,
      expiresAt: expiresAt,
      sourceConversationId: sourceConversationId,
      sourceMessageId: sourceMessageId,
      owner: owner,
    );
  }

  @override
  Future<MemoryWriteResult> suggest({
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
  }) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return _accessDenied;
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess) return guard;
    if (!owner.isCurrent) return _accessDenied;
    if (!_settings.suggestionsEnabled) {
      return const MemoryWriteResult(
        MemoryWriteOutcome.disabled,
        'Memory suggestions are turned off for this workspace.',
      );
    }
    return _create(
      content: content,
      category: category,
      status: MemoryStatus.pending,
      tags: tags,
      expiresAt: expiresAt,
      sourceConversationId: sourceConversationId,
      sourceMessageId: sourceMessageId,
      owner: owner,
    );
  }

  Future<MemoryWriteResult> _create({
    required String content,
    required MemoryCategory category,
    required MemoryStatus status,
    required List<String> tags,
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
    required ProfileOperationOwner owner,
  }) async {
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess) return guard;
    if (!owner.isCurrent) return _accessDenied;
    final String clean = content.trim();
    final String? sensitive = MemorySafety.rejectionFor(clean);
    if (sensitive != null) {
      return MemoryWriteResult(MemoryWriteOutcome.sensitiveContent, sensitive);
    }
    final DateTime now = DateTime.now();
    final MemoryRecord record = MemoryRecord(
      id: MemoryRecord.newId(),
      profile: profile,
      content: clean,
      category: category,
      status: status,
      tags: _cleanTags(tags),
      createdAt: now,
      updatedAt: now,
      expiresAt: expiresAt,
      sourceConversationId: sourceConversationId,
      sourceMessageId: sourceMessageId,
    );
    final String? validation = record.validationError;
    if (validation != null) {
      return MemoryWriteResult(MemoryWriteOutcome.invalid, validation);
    }
    if (_records.length >= AuraRuntimeConfig.maxMemoryRecords) {
      return const MemoryWriteResult(
        MemoryWriteOutcome.invalid,
        'This workspace has reached its memory limit. Remove a memory first.',
      );
    }
    return _commit(<MemoryRecord>[..._records, record], owner);
  }

  @override
  Future<MemoryWriteResult> approve(String id) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return _accessDenied;
    return _setStatus(id, MemoryStatus.approved, owner);
  }

  @override
  Future<MemoryWriteResult> reject(String id) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return _accessDenied;
    return _setStatus(id, MemoryStatus.rejected, owner);
  }

  Future<MemoryWriteResult> _setStatus(
    String id,
    MemoryStatus status,
    ProfileOperationOwner owner,
  ) async {
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess) return guard;
    if (!owner.isCurrent) return _accessDenied;
    final int index = _records.indexWhere((MemoryRecord item) => item.id == id);
    if (index < 0 || _records[index].profile != profile) {
      return const MemoryWriteResult(
        MemoryWriteOutcome.notFound,
        'That memory is no longer available.',
      );
    }
    final List<MemoryRecord> next = List<MemoryRecord>.from(_records);
    next[index] = next[index].copyWith(
      status: status,
      updatedAt: DateTime.now(),
    );
    return _commit(next, owner);
  }

  @override
  Future<MemoryWriteResult> update({
    required String id,
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
  }) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return _accessDenied;
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess) return guard;
    if (!owner.isCurrent) return _accessDenied;
    final int index = _records.indexWhere((MemoryRecord item) => item.id == id);
    if (index < 0 || _records[index].profile != profile) {
      return const MemoryWriteResult(
        MemoryWriteOutcome.notFound,
        'That memory is no longer available.',
      );
    }
    final String clean = content.trim();
    final String? sensitive = MemorySafety.rejectionFor(clean);
    if (sensitive != null) {
      return MemoryWriteResult(MemoryWriteOutcome.sensitiveContent, sensitive);
    }
    final MemoryRecord edited = _records[index].copyWith(
      content: clean,
      category: category,
      tags: _cleanTags(tags),
      updatedAt: DateTime.now(),
      expiresAt: expiresAt,
      clearExpiresAt: expiresAt == null,
    );
    final String? validation = edited.validationError;
    if (validation != null) {
      return MemoryWriteResult(MemoryWriteOutcome.invalid, validation);
    }
    final List<MemoryRecord> next = List<MemoryRecord>.from(_records);
    next[index] = edited;
    return _commit(next, owner);
  }

  @override
  Future<MemoryWriteResult> delete(String id) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return _accessDenied;
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess) return guard;
    if (!owner.isCurrent) return _accessDenied;
    final bool exists = _records.any(
      (MemoryRecord item) => item.id == id && item.profile == profile,
    );
    if (!exists) {
      return const MemoryWriteResult(
        MemoryWriteOutcome.notFound,
        'That memory is no longer available.',
      );
    }
    return _commit(
      _records.where((MemoryRecord item) => item.id != id).toList(),
      owner,
    );
  }

  @override
  Future<MemoryWriteResult> clear() async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return _accessDenied;
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess) return guard;
    if (!owner.isCurrent) return _accessDenied;
    return _commit(const <MemoryRecord>[], owner);
  }

  @override
  Future<List<MemoryRecord>> retrieve({
    required String query,
    required DateTime now,
    int limit = AuraRuntimeConfig.maxMemoryContextItems,
  }) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return const <MemoryRecord>[];
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess || !owner.isCurrent || !_settings.retrievalEnabled) {
      return const <MemoryRecord>[];
    }
    return MemoryRetrieval.rank(
      candidates: _records
          .where((MemoryRecord item) => item.profile == profile)
          .toList(growable: false),
      query: query,
      now: now,
      limit: limit,
    );
  }

  @override
  Future<void> markAccessed(List<String> ids) async {
    final ProfileOperationOwner? owner = _beginOwner();
    if (owner == null) return;
    final MemoryWriteResult guard = await _guard(owner);
    if (!guard.isSuccess || !owner.isCurrent || ids.isEmpty) return;
    final Set<String> targets = ids.toSet();
    final DateTime now = DateTime.now();
    final List<MemoryRecord> next = <MemoryRecord>[];
    bool changed = false;
    for (final MemoryRecord record in _records) {
      if (record.profile == profile &&
          targets.contains(record.id) &&
          record.status == MemoryStatus.approved) {
        next.add(record.copyWith(lastAccessedAt: now));
        changed = true;
      } else {
        next.add(record);
      }
    }
    if (changed) await _commit(next, owner);
  }

  @override
  void discardForLock() {
    _records = const <MemoryRecord>[];
    _settings = MemorySettings.defaults;
    _loaded = false;
    _storageError = null;
  }

  static List<String> _cleanTags(List<String> tags) =>
      List<String>.unmodifiable(
        tags
            .map((String tag) => tag.trim())
            .where(
              (String tag) =>
                  tag.isNotEmpty &&
                  tag.length <= AuraRuntimeConfig.maxMemoryTagChars,
            )
            .take(AuraRuntimeConfig.maxMemoryTags)
            .toList(),
      );
}
