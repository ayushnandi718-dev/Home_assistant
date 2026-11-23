import 'dart:async';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/features/ai/domain/ai_memory_context.dart';
import 'package:aura_hub/features/memory/data/encrypted_memory_store.dart';
import 'package:aura_hub/features/memory/data/memory_ai_source.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/memory_repository.dart';
import 'package:aura_hub/features/memory/data/memory_settings_store.dart';
import 'package:aura_hub/features/memory/data/memory_store.dart';
import 'package:aura_hub/features/memory/data/windows_dpapi_memory_cipher.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/memory/domain/memory_status.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Transient memory UI state. Never contains provider prompts or credentials.
class MemoryState {
  const MemoryState({
    this.records = const <MemoryRecord>[],
    this.settings = MemorySettings.defaults,
    this.isLoading = false,
    this.errorMessage,
    this.storageError = false,
  });

  final List<MemoryRecord> records;
  final MemorySettings settings;
  final bool isLoading;
  final String? errorMessage;

  /// True when the error requires file recovery, not a simple retry.
  final bool storageError;

  bool get hasError => errorMessage != null;

  List<MemoryRecord> get approved => records
      .where((MemoryRecord item) => item.status == MemoryStatus.approved)
      .toList(growable: false);

  List<MemoryRecord> get pending => records
      .where((MemoryRecord item) => item.status == MemoryStatus.pending)
      .toList(growable: false);

  MemoryState copyWith({
    List<MemoryRecord>? records,
    MemorySettings? settings,
    bool? isLoading,
    String? errorMessage,
    bool? storageError,
    bool clearError = false,
  }) {
    return MemoryState(
      records: records ?? this.records,
      settings: settings ?? this.settings,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
      storageError: storageError ?? this.storageError,
    );
  }
}

/// Drives the memory screen through the application-controlled repository.
class MemoryController extends StateNotifier<MemoryState> {
  MemoryController(this._repository,
      {required ProfileAccessReader accessReader})
      : _accessReader = accessReader,
        super(const MemoryState()) {
    unawaited(load());
  }

  final MemoryRepository _repository;
  final ProfileAccessReader _accessReader;
  int _generation = 0;

  ProfileOperationOwner _newOwner() => ProfileOperationOwner(
        accessReader: _accessReader,
        profile: _repository.profile,
      );

  bool _isCurrent(ProfileOperationOwner owner, int generation) =>
      owner.isCurrent && generation == _generation;

  Future<void> load() async {
    final int generation = ++_generation;
    final ProfileOperationOwner owner;
    try {
      owner = _newOwner();
    } on AuraProfileAccessDenied {
      state = const MemoryState();
      return;
    }
    state = state.copyWith(isLoading: true, clearError: true);
    final List<MemoryRecord> records = await _repository.load();
    if (!mounted || !_isCurrent(owner, generation)) return;

    final String? storageError = _repository is MemoryStorageStatusReader
        ? (_repository as MemoryStorageStatusReader).storageErrorMessage
        : null;
    if (storageError != null) {
      state = MemoryState(
        isLoading: false,
        errorMessage: storageError,
        storageError: true,
      );
      return;
    }

    final MemorySettings settings = await _repository.loadSettings();
    if (!mounted || !_isCurrent(owner, generation)) return;
    final String? settingsError = _repository is MemoryStorageStatusReader
        ? (_repository as MemoryStorageStatusReader).storageErrorMessage
        : null;
    if (settingsError != null) {
      state = MemoryState(
        isLoading: false,
        errorMessage: settingsError,
        storageError: true,
      );
      return;
    }
    state = MemoryState(
      records: records,
      settings: settings,
      isLoading: false,
    );
  }

  Future<bool> _mutate(Future<MemoryWriteResult> Function() action) async {
    final int generation = _generation;
    final ProfileOperationOwner owner;
    try {
      owner = _newOwner();
    } on AuraProfileAccessDenied {
      return false;
    }
    final MemoryWriteResult result = await action();
    if (!mounted || !_isCurrent(owner, generation)) return false;
    return _apply(result);
  }

  Future<bool> _apply(MemoryWriteResult result) async {
    if (!result.isSuccess) {
      if (mounted) {
        state = state.copyWith(
          isLoading: false,
          errorMessage: result.userMessage ??
              'That memory change could not be completed.',
          storageError:
              result.outcome == MemoryWriteOutcome.storageSecurityError,
        );
      }
      return false;
    }
    await load();
    return true;
  }

  Future<bool> createApproved({
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
  }) =>
      _mutate(
        () => _repository.createApproved(
          content: content,
          category: category,
          tags: tags,
          expiresAt: expiresAt,
          sourceConversationId: sourceConversationId,
          sourceMessageId: sourceMessageId,
        ),
      );

  Future<bool> suggest({
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
    String? sourceConversationId,
    String? sourceMessageId,
  }) =>
      _mutate(
        () => _repository.suggest(
          content: content,
          category: category,
          tags: tags,
          expiresAt: expiresAt,
          sourceConversationId: sourceConversationId,
          sourceMessageId: sourceMessageId,
        ),
      );

  Future<bool> approve(String id) => _mutate(() => _repository.approve(id));

  Future<bool> reject(String id) => _mutate(() => _repository.reject(id));

  Future<bool> update({
    required String id,
    required String content,
    required MemoryCategory category,
    List<String> tags = const <String>[],
    DateTime? expiresAt,
  }) =>
      _mutate(
        () => _repository.update(
          id: id,
          content: content,
          category: category,
          tags: tags,
          expiresAt: expiresAt,
        ),
      );

  Future<bool> delete(String id) => _mutate(() => _repository.delete(id));

  Future<bool> clear() => _mutate(_repository.clear);

  Future<bool> setSettings(MemorySettings settings) =>
      _mutate(() => _repository.saveSettings(settings));

  /// Called when the AYUSH session is locked or the workspace changes.
  void discardForLock() {
    _generation++;
    state = const MemoryState();
  }
}

void _guardMemoryProfile(Ref ref, AuraProfile profile) {
  ref.read(profileAccessProvider).requirePrivate(profile, true);
}

void _watchMemoryLock(Ref ref, AuraProfile profile, void Function() onLocked) {
  ref.listen<ProfileSession>(profileSessionProvider, (_, ProfileSession next) {
    if (!ProfileAccess(next).canRead(profile)) onLocked();
  });
}

/// Encryption boundary for private AYUSH memory.
///
/// Overridable in tests. On non-Windows platforms the unsupported cipher keeps
/// AYUSH fail-closed instead of silently writing plaintext.
final Provider<MemoryCipher> ayushMemoryCipherProvider =
    Provider<MemoryCipher>((Ref ref) {
  if (!Platform.isWindows) return const UnsupportedMemoryCipher();
  return WindowsDpapiMemoryCipher();
});

final ProviderFamily<MemoryRecordStore, AuraProfile> memoryStoreForProvider =
    ProviderFamily<MemoryRecordStore, AuraProfile>(
  (Ref ref, AuraProfile profile) {
    if (profile == AuraProfile.ayush) {
      return EncryptedMemoryStore(
        profile: profile,
        cipher: ref.read(ayushMemoryCipherProvider),
      );
    }
    return MemoryStore(profile: profile);
  },
);

final ProviderFamily<MemorySettingsStorage, AuraProfile>
    memorySettingsStoreForProvider =
    ProviderFamily<MemorySettingsStorage, AuraProfile>(
  (Ref ref, AuraProfile profile) {
    if (profile == AuraProfile.ayush) {
      return EncryptedMemorySettingsStore(
        profile: profile,
        cipher: ref.read(ayushMemoryCipherProvider),
      );
    }
    return MemorySettingsStore(profile: profile);
  },
);

final ProviderFamily<MemoryRepository, AuraProfile>
    memoryRepositoryForProvider = ProviderFamily<MemoryRepository, AuraProfile>(
  (Ref ref, AuraProfile profile) {
    _guardMemoryProfile(ref, profile);
    final LocalMemoryRepository repository = LocalMemoryRepository(
      profile: profile,
      store: ref.read(memoryStoreForProvider(profile)),
      settingsStore: ref.read(memorySettingsStoreForProvider(profile)),
      accessReader: () => ref.read(profileAccessProvider),
    );
    return repository;
  },
);

final ProviderFamily<AiMemorySource, AuraProfile> memoryAiSourceForProvider =
    ProviderFamily<AiMemorySource, AuraProfile>(
  (Ref ref, AuraProfile profile) => MemoryAiSource(
    ref.read(memoryRepositoryForProvider(profile)),
  ),
);

final StateNotifierProviderFamily<MemoryController, MemoryState, AuraProfile>
    memoryControllerForProvider =
    StateNotifierProviderFamily<MemoryController, MemoryState, AuraProfile>(
  (Ref ref, AuraProfile profile) {
    final MemoryController controller = MemoryController(
      ref.read(memoryRepositoryForProvider(profile)),
      accessReader: () => ref.read(profileAccessProvider),
    );
    _watchMemoryLock(ref, profile, () {
      ref.read(memoryRepositoryForProvider(profile)).discardForLock();
      controller.discardForLock();
    });
    return controller;
  },
);

final Provider<MemoryRepository> activeMemoryRepositoryProvider =
    Provider<MemoryRepository>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(memoryRepositoryForProvider(profile));
});

final Provider<MemoryController> activeMemoryControllerProvider =
    Provider<MemoryController>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(memoryControllerForProvider(profile).notifier);
});

final Provider<MemoryState> activeMemoryStateProvider =
    Provider<MemoryState>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(memoryControllerForProvider(profile));
});

final Provider<MemorySettings> activeMemorySettingsProvider =
    Provider<MemorySettings>((Ref ref) {
  return ref.watch(activeMemoryStateProvider).settings;
});
