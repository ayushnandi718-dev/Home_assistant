import 'dart:async';
import 'package:aura_hub/core/platform/io_compat.dart';
import 'dart:math';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/core/platform/platform_capabilities.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_storage_envelope.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/data/encrypted_ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/ai_preferences_store.dart';
import 'package:aura_hub/features/ai/data/default_ai_context_assembler.dart';
import 'package:aura_hub/features/ai/data/default_ai_provider_registry.dart';
import 'package:aura_hub/features/ai/data/ollama_ai_adapter.dart';
import 'package:aura_hub/features/ai/data/openai_compatible_client.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_context.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/ai/domain/ai_diagnostics.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_input_policy.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_memory_context.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_models.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_registry.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_selection.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_router.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/windows_dpapi_memory_cipher.dart';
import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest, testable readiness shown in the AI header.
enum AiReadiness {
  unconfigured,
  needsConfiguration,
  needsCredential,
  disconnected,
  needsRefresh,
  connected,
  error,
  unavailable,
}

extension AiReadinessX on AiReadiness {
  String get label {
    switch (this) {
      case AiReadiness.unconfigured:
        return 'NO PROVIDER CONFIGURED';
      case AiReadiness.needsConfiguration:
        return 'CONFIGURATION NEEDED';
      case AiReadiness.needsCredential:
        return 'API KEY NEEDED';
      case AiReadiness.disconnected:
        return 'NOT TESTED';
      case AiReadiness.needsRefresh:
        return 'RETEST NEEDED';
      case AiReadiness.connected:
        return 'METADATA VERIFIED';
      case AiReadiness.error:
        return 'CONNECTION ERROR';
      case AiReadiness.unavailable:
        return 'PROVIDER UNAVAILABLE';
    }
  }
}

/// Separate chat-state badge. A verified `/models` test never implies that the
/// last `/chat/completions` request succeeded.
enum AiChatStatus { idle, running, failed }

extension AiChatStatusX on AiChatStatus {
  String get label {
    switch (this) {
      case AiChatStatus.idle:
        return 'CHAT READY';
      case AiChatStatus.running:
        return 'CHAT RUNNING';
      case AiChatStatus.failed:
        return 'LAST CHAT FAILED';
    }
  }
}

/// Non-secret provider configs for one profile.
class AiConfigController extends StateNotifier<List<AiProviderConfig>> {
  AiConfigController({
    required AuraProfile profile,
    AiConfigStore? store,
    AuraLogger? logger,
    required ProfileAccessReader accessReader,
  })  : _profile = profile,
        _store = store ?? AiConfigStore(profile: profile),
        _logger = logger ?? AuraLogger(),
        _accessReader = accessReader,
        super(const <AiProviderConfig>[]) {
    unawaited(load());
  }

  final AuraProfile _profile;
  final AiConfigStore _store;
  final AuraLogger _logger;
  final ProfileAccessReader _accessReader;

  AuraProfile get profile => _profile;

  /// Exposed only so startup/seam tests can prove an explicit reader was
  /// supplied. Security checks call the reader at operation time.
  ProfileAccessReader get accessReader => _accessReader;

  bool _canRead() => _accessReader().canRead(_profile);

  ProfileOperationOwner _newOwner() => ProfileOperationOwner(
        accessReader: _accessReader,
        profile: _profile,
      );

  Future<void> load() async {
    // Reads stay truthfully empty while locked. The constructor's eager load
    // must never throw an unhandled authorization error.
    late final ProfileOperationOwner owner;
    try {
      owner = _newOwner();
    } on AuraProfileAccessDenied {
      state = const <AiProviderConfig>[];
      return;
    }
    try {
      final List<AiProviderConfig> loaded = await _store.load();
      if (!owner.isCurrent) return;
      state = loaded;
    } on AuraProfileAccessDenied {
      if (owner.isCurrent) state = const <AiProviderConfig>[];
    } catch (_) {
      if (owner.isCurrent) state = const <AiProviderConfig>[];
    }
  }

  List<AiProviderConfig> get enabledProviders {
    if (!_canRead()) return const <AiProviderConfig>[];
    return state
        .where((AiProviderConfig config) => config.enabled)
        .toList(growable: false);
  }

  Future<void> upsert(AiProviderConfig config) async {
    final ProfileOperationOwner owner = _newOwner();
    final List<AiProviderConfig> next = await _store.upsert(config);
    if (!owner.isCurrent) return;
    state = next;
    _logger.info('ai', 'Provider config saved for ${_profile.storageScope}.');
  }

  /// Persists a validated model choice on an existing provider.
  ///
  /// The model identifier is the value sent on the wire by the existing
  /// adapters, so this is the single source of truth for model selection. An
  /// invalid id is rejected before any store write or provider request.
  Future<bool> selectModel(String providerId, String modelId) async {
    final ProfileOperationOwner owner = _newOwner();
    final String? error = AiProviderSelection.validateModelId(modelId);
    if (error != null) return false;
    final AiProviderConfig? config =
        AiProviderSelection.byId(state, providerId);
    if (config == null) return false;
    final AiProviderConfig next = config.copyWith(model: modelId.trim());
    if (next.model == config.model) return true;
    if (next.validateEndpoint() != null) return false;
    if (!owner.isCurrent) return false;
    await upsert(next);
    return owner.isCurrent;
  }

  Future<void> clear() async {
    final ProfileOperationOwner owner = _newOwner();
    await _store.save(const <AiProviderConfig>[]);
    if (!owner.isCurrent) return;
    state = const <AiProviderConfig>[];
    _logger.info('ai', 'Provider configs cleared for ${_profile.storageScope}');
  }

  void discardForLock() => state = const <AiProviderConfig>[];
}

/// Persisted language, consent and selection state for one profile.
class AiPreferencesController extends StateNotifier<AiPreferences> {
  AiPreferencesController({
    required AuraProfile profile,
    AiPreferencesStore? store,
    required ProfileAccessReader accessReader,
  })  : _profile = profile,
        _store = store ?? AiPreferencesStore(profile: profile),
        _accessReader = accessReader,
        super(const AiPreferences()) {
    unawaited(load());
  }

  final AuraProfile _profile;
  final AiPreferencesStore _store;
  final ProfileAccessReader _accessReader;
  int _generation = 0;

  /// Exposed only for explicit-reader seam tests.
  ProfileAccessReader get accessReader => _accessReader;

  AiPreferences _persistable(AiPreferences value) =>
      _profile == AuraProfile.ayush
          ? value.copyWith(clearActiveConversation: true)
          : value;

  ({ProfileOperationOwner owner, int generation}) _begin() => (
        owner: ProfileOperationOwner(
          accessReader: _accessReader,
          profile: _profile,
        ),
        generation: _generation,
      );

  bool _isCurrent(
    ProfileOperationOwner owner,
    int generation,
  ) =>
      owner.isCurrent && generation == _generation;

  Future<void> load() async {
    final int generation = ++_generation;
    final ProfileOperationOwner owner = ProfileOperationOwner(
      accessReader: _accessReader,
      profile: _profile,
    );
    final AiPreferences loaded = await _store.load();
    if (!_isCurrent(owner, generation)) return;

    final AiPreferences safe = _persistable(loaded);
    state = safe;
    // Older AYUSH builds may have written a private pointer. Remove it once so
    // a later unlock cannot resurrect it from the plaintext prefs file.
    if (_profile == AuraProfile.ayush && loaded.activeConversationId != null) {
      bool isCurrent() => _isCurrent(owner, generation);
      try {
        if (!isCurrent()) return;
        await _store.save(safe, isWriteAllowed: isCurrent);
        if (!isCurrent()) return;
      } on AuraProfileAccessDenied {
        // A lock during cleanup leaves the in-memory state cleared; a later
        // unlock retries the migration.
      } catch (_) {
        // Preference cleanup is best-effort; private state stays in memory.
      }
    }
  }

  /// Drops in-memory AYUSH pointers and invalidates stale loads.
  void discardForLock() {
    _generation++;
    state = const AiPreferences();
  }

  Future<void> setLanguage(AiLanguage language) async {
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    if (state.language == language) return;
    state = state.copyWith(language: language);
    await _persist(op.owner, op.generation);
  }

  Future<void> setConsent(bool granted) async {
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    if (state.consentGranted == granted) return;
    state = state.copyWith(consentGranted: granted);
    await _persist(op.owner, op.generation);
  }

  Future<void> selectProvider(String? providerId) async {
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    if (state.selectedProviderId == providerId) return;
    state = providerId == null
        ? state.copyWith(clearSelectedProvider: true)
        : state.copyWith(selectedProviderId: providerId);
    await _persist(op.owner, op.generation);
  }

  Future<void> setActiveConversation(String? conversationId) async {
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    if (state.activeConversationId == conversationId) return;
    state = conversationId == null
        ? state.copyWith(clearActiveConversation: true)
        : state.copyWith(activeConversationId: conversationId);
    await _persist(op.owner, op.generation);
  }

  Future<void> _persist(ProfileOperationOwner owner, int generation) async {
    bool isCurrent() => _isCurrent(owner, generation);
    if (!isCurrent()) {
      throw AuraProfileAccessDenied(_profile);
    }
    // An AYUSH active-conversation pointer is private conversation metadata.
    // Consent and non-secret provider selection still persist as before, but a
    // private session always resumes with no remembered private conversation.
    await _store.save(_persistable(state), isWriteAllowed: isCurrent);
    if (!isCurrent()) throw AuraProfileAccessDenied(_profile);
  }
}

/// DPAPI entropy for AYUSH conversations is distinct from AYUSH memory. Both
/// use the same native cipher implementation, but neither envelope can be
/// decrypted with the other profile feature's protection context.
MemoryCipher conversationCipherForPlatform() => Platform.isWindows
    ? WindowsDpapiMemoryCipher(
        entropy: AiConversationStorageEnvelope.dpapiEntropy,
      )
    : const UnsupportedMemoryCipher();

/// Injectable encryption boundary for private conversation history.
final Provider<MemoryCipher> ayushConversationCipherProvider =
    Provider<MemoryCipher>((Ref ref) => conversationCipherForPlatform());

AiConversationStorage _defaultAiConversationStorage(AuraProfile profile) =>
    profile == AuraProfile.family
        ? AiConversationStore(profile: profile)
        : EncryptedAiConversationStore(
            profile: profile,
            cipher: conversationCipherForPlatform(),
          );

/// Bounded, profile-bound conversation list for one profile.
///
/// The public surface intentionally matches the pre-repository controller so
/// chat, context assembly, and markdown rendering remain unchanged.
class AiConversationLibraryController
    extends StateNotifier<List<AiConversation>> {
  AiConversationLibraryController({
    required AuraProfile profile,
    AiConversationRepository? repository,
    AiConversationStorage? storage,
    AiConversationStore? store,
    required ProfileAccessReader accessReader,
    DateTime Function()? now,
  })  : _profile = profile,
        _repository = repository ??
            ProfileBoundAiConversationRepository(
              profile: profile,
              storage:
                  storage ?? store ?? _defaultAiConversationStorage(profile),
              accessReader: accessReader,
            ),
        _accessReader = accessReader,
        _now = now ?? DateTime.now,
        super(const <AiConversation>[]) {
    unawaited(load());
  }

  final AuraProfile _profile;
  final AiConversationRepository _repository;
  final ProfileAccessReader _accessReader;
  final DateTime Function() _now;
  final ValueNotifier<AiConversationRecoveryState> recoveryNotifier =
      ValueNotifier<AiConversationRecoveryState>(
    const AiConversationRecoveryState(),
  );
  int _generation = 0;

  /// Exposed only for explicit-reader seam tests.
  ProfileAccessReader get accessReader => _accessReader;

  ({ProfileOperationOwner owner, int generation}) _begin() => (
        owner: ProfileOperationOwner(
          accessReader: _accessReader,
          profile: _profile,
        ),
        generation: _generation,
      );

  bool _isCurrent(
    ProfileOperationOwner owner,
    int generation,
  ) =>
      owner.isCurrent && generation == _generation;

  /// Last load/write outcome, exposed for the history panel's error state.
  AiConversationRecoveryState get recovery => recoveryNotifier.value;

  @override
  void dispose() {
    recoveryNotifier.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final int generation = ++_generation;
    _setRecovery(AiConversationLoadPhase.loading);
    try {
      final ProfileOperationOwner owner = ProfileOperationOwner(
        accessReader: _accessReader,
        profile: _profile,
      );
      final AiConversationLoadResult result = await _repository.load();
      if (!_isCurrent(owner, generation)) return;
      state = result.conversations;
      switch (result.outcome) {
        case AiConversationLoadOutcome.ready:
          _setRecovery(AiConversationLoadPhase.ready);
        case AiConversationLoadOutcome.recovered:
          _setRecovery(
            AiConversationLoadPhase.recovered,
            result.detail ?? 'Conversation history was recovered.',
          );
        case AiConversationLoadOutcome.failed:
          _setRecovery(
            AiConversationLoadPhase.failed,
            result.detail ?? 'Conversation history could not be loaded.',
          );
      }
    } on AuraProfileAccessDenied {
      if (generation == _generation) {
        _setRecovery(AiConversationLoadPhase.idle);
      }
    } catch (error) {
      if (generation == _generation) {
        _setRecovery(
          AiConversationLoadPhase.failed,
          'Conversation history could not be loaded.',
        );
      }
    }
  }

  /// Clears private state and invalidates every in-flight load.
  void discardForLock() {
    _generation++;
    state = const <AiConversation>[];
    _setRecovery(AiConversationLoadPhase.idle);
    if (_profile == AuraProfile.ayush) {
      unawaited(_repository.clearSession().catchError((Object _) {}));
    }
  }

  String create() {
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    final DateTime now = _now();
    final String id =
        '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(65536).toRadixString(16)}';
    final AiConversation conversation = AiConversation(
      id: id,
      profileScope: _profile.storageScope,
      createdAt: now,
      updatedAt: now,
    );
    state = <AiConversation>[conversation, ...state]
        .take(AuraRuntimeConfig.maxAiConversations)
        .toList(growable: false);
    unawaited(_persist(op));
    return id;
  }

  bool contains(String id) => state.any((AiConversation item) => item.id == id);

  Future<void> rename(String id, String title) async {
    final String clean = title.trim();
    if (clean.isEmpty) return;
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    state = state
        .map(
          (AiConversation item) => item.id == id
              ? item.copyWith(title: clean, updatedAt: _now())
              : item,
        )
        .toList();
    _sort();
    await _persist(op);
  }

  Future<void> delete(String id) async {
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    state = state
        .where((AiConversation item) => item.id != id)
        .toList(growable: false);
    await _persist(op);
  }

  void appendMessage(String conversationId, AiMessage message) {
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    AiConversation? conversation;
    for (final AiConversation item in state) {
      if (item.id == conversationId) {
        conversation = item;
        break;
      }
    }
    if (conversation == null) return;

    final bool duplicate = conversation.list().any((AiMessage existing) {
      if (message.id != null && existing.id == message.id) return true;
      return existing.role == message.role &&
          existing.content == message.content &&
          existing.timestamp == message.timestamp &&
          existing.delivery == message.delivery;
    });
    if (duplicate) return;

    final String id = message.id?.isNotEmpty == true
        ? message.id!
        : 'm-${message.timestamp.microsecondsSinceEpoch}-'
            '${Random.secure().nextInt(65536).toRadixString(16)}';
    final AiMessage scoped = message.copyWith(
      id: id,
      conversationId: conversationId,
      delivery: message.delivery == AiMessageDelivery.streaming
          ? AiMessageDelivery.interrupted
          : message.delivery,
    );
    state = state
        .map(
          (AiConversation item) =>
              item.id == conversationId ? item.append(scoped) : item,
        )
        .toList(growable: false);
    _sort();
    unawaited(_persist(op));
  }

  Future<void> clear(String conversationId) async {
    final ({ProfileOperationOwner owner, int generation}) op = _begin();
    state = state
        .map(
          (AiConversation item) =>
              item.id == conversationId ? item.clear(now: _now()) : item,
        )
        .toList(growable: false);
    await _persist(op);
  }

  void _sort() {
    final List<AiConversation> sorted = List<AiConversation>.from(state)
      ..sort((AiConversation a, AiConversation b) =>
          b.sortTime.compareTo(a.sortTime));
    state = sorted;
  }

  Future<void> _persist(
    ({ProfileOperationOwner owner, int generation}) op,
  ) async {
    if (!_isCurrent(op.owner, op.generation)) return;
    final List<AiConversation> snapshot = List<AiConversation>.unmodifiable(
      state,
    );
    try {
      await _repository.save(snapshot);
    } on AuraProfileAccessDenied {
      // Lock handling already cleared the visible state.
    } on AiConversationStorageException catch (error) {
      if (_isCurrent(op.owner, op.generation)) {
        // Storage exceptions carry fixed, content-free recovery messages.
        _setRecovery(AiConversationLoadPhase.failed, error.message);
      }
    } catch (_) {
      if (_isCurrent(op.owner, op.generation)) {
        _setRecovery(
          AiConversationLoadPhase.failed,
          'Conversation changes could not be saved.',
        );
      }
    }
  }

  void _setRecovery(
    AiConversationLoadPhase phase, [
    String? message,
  ]) {
    if (!mounted) return;
    recoveryNotifier.value = recoveryNotifier.value.next(
      phase: phase,
      message: message,
    );
  }
}

/// Transient chat UI state. Never contains prompts, responses or credentials.
class AiChatState {
  const AiChatState({
    this.isBusy = false,
    this.streamingText,
    this.failureKind,
    this.errorMessage,
  });

  final bool isBusy;
  final String? streamingText;
  final AiFailureKind? failureKind;
  final String? errorMessage;

  bool get hasError => errorMessage != null;

  AiChatState copyWith({
    bool? isBusy,
    String? streamingText,
    AiFailureKind? failureKind,
    String? errorMessage,
    bool clearStream = false,
    bool clearError = false,
  }) {
    return AiChatState(
      isBusy: isBusy ?? this.isBusy,
      streamingText: clearStream ? null : streamingText ?? this.streamingText,
      failureKind: clearError ? null : failureKind ?? this.failureKind,
      errorMessage: clearError ? null : errorMessage ?? this.errorMessage,
    );
  }
}

/// Sends messages, owns cancellation and persists only completed content.
class AiChatController extends StateNotifier<AiChatState> {
  AiChatController({
    required this.profile,
    required this.access,
    required AiConfigController configs,
    required AiPreferencesController preferences,
    required AiConversationLibraryController conversations,
    required AiCredentialController credentials,
    required AiClient client,
    required AuraLogger logger,
    required ProfileAccessReader accessReader,
    DateTime Function()? now,
    AiDiagnostics? diagnostics,
    AiContextAssembler? contextAssembler,
    AiMemorySource? memorySource,
    bool ollamaAvailable = true,
  })  : _accessReader = accessReader,
        _now = now ?? DateTime.now,
        _configs = configs,
        _preferences = preferences,
        _conversations = conversations,
        _credentials = credentials,
        _client = client,
        _logger = logger,
        _diagnostics = diagnostics ?? const NoAiDiagnostics(),
        _contextAssembler =
            contextAssembler ?? const DefaultAiContextAssembler(),
        _memorySource = memorySource ?? const NoAiMemorySource(),
        _ollamaAvailable = ollamaAvailable,
        super(const AiChatState());

  final AuraProfile profile;
  final ProfileAccess access;
  final ProfileAccessReader _accessReader;
  final DateTime Function() _now;

  /// Exposed only for explicit-reader seam tests.
  ProfileAccessReader get accessReader => _accessReader;
  final AiConfigController _configs;
  final AiPreferencesController _preferences;
  final AiConversationLibraryController _conversations;
  final AiCredentialController _credentials;
  final AiClient _client;
  final AuraLogger _logger;
  final AiDiagnostics _diagnostics;
  final AiContextAssembler _contextAssembler;
  final AiMemorySource _memorySource;
  final bool _ollamaAvailable;

  // Single-owner generation model. `_activeGeneration` is the authoritative
  // in-flight guard and is set synchronously before any await; `state.isBusy`
  // mirrors it for the switch coordinator and the UI. `_lockGeneration`
  // invalidates work whose private session ended mid-operation. Generation ids
  // are globally monotonic so a stale operation can never clear a newer one's
  // guard, even after lock cleanup releases the previous guard.
  int _nextGeneration = 0;
  int _activeGeneration = 0;
  int _lockGeneration = 0;
  AiCancelToken? _cancelToken;
  String? _lastPrompt;

  /// Public read-only view for provider switching. No state mutation is exposed.
  bool get isBusy => state.isBusy;

  bool _isCurrent(int generation, int lockGeneration) =>
      generation == _activeGeneration && lockGeneration == _lockGeneration;

  ({int generation, int lockGeneration, AiCancelToken token})
      _beginGeneration() {
    final int generation = ++_nextGeneration;
    _activeGeneration = generation;
    final AiCancelToken token = AiCancelToken();
    _cancelToken = token;
    state = const AiChatState(isBusy: true, streamingText: '');
    return (
      generation: generation,
      lockGeneration: _lockGeneration,
      token: token
    );
  }

  void _endGeneration(int generation, AiCancelToken token) {
    if (identical(_cancelToken, token)) _cancelToken = null;
    if (_activeGeneration != generation) return;
    _activeGeneration = 0;
    // Early returns before the first stream (for example a cancellation while
    // credentials are resolving) previously left the UI busy forever. Only the
    // generation that still owns the controller may clear this state; a newer
    // generation's busy indicator is never touched.
    if (state.isBusy || state.streamingText != null) {
      state = state.copyWith(isBusy: false, clearStream: true);
    }
  }

  Future<void> send(String rawText) async {
    final String text = rawText.trim();
    if (text.isEmpty || _activeGeneration != 0) return;

    late final ProfileOperationOwner owner;
    try {
      owner =
          ProfileOperationOwner(accessReader: _accessReader, profile: profile);
    } on AuraProfileAccessDenied {
      state = const AiChatState(
        failureKind: AiFailureKind.configuration,
        errorMessage: 'Unlock the private workspace before sending a message.',
      );
      return;
    }
    if (!_preferences.state.consentGranted) {
      state = const AiChatState(
        failureKind: AiFailureKind.consentRequired,
        errorMessage: 'External AI requests require your explicit consent.',
      );
      return;
    }
    if (AiInputPolicy.isBlocked(text)) {
      showBlockedInput();
      return;
    }

    final ({int generation, int lockGeneration, AiCancelToken token}) op =
        _beginGeneration();
    try {
      String conversationId = _preferences.state.activeConversationId ?? '';
      if (!_conversations.contains(conversationId)) {
        conversationId = _conversations.create();
        await _preferences.setActiveConversation(conversationId);
        if (!owner.isCurrent ||
            !_isCurrent(op.generation, op.lockGeneration) ||
            op.token.isCancelled) {
          return;
        }
      }
      _conversations.appendMessage(
        conversationId,
        AiMessage(
          role: AiMessageRole.user,
          content: text,
          timestamp: _now(),
        ),
      );
      _lastPrompt = text;
      await _runCompletion(
        conversationId: conversationId,
        owner: owner,
        generation: op.generation,
        lockGeneration: op.lockGeneration,
        token: op.token,
      );
    } finally {
      _endGeneration(op.generation, op.token);
    }
  }

  /// Retries the last user prompt without duplicating it in the transcript.
  Future<void> retry() async {
    final String? conversationId = _preferences.state.activeConversationId;
    if (_lastPrompt == null ||
        conversationId == null ||
        _activeGeneration != 0) {
      return;
    }
    final ProfileOperationOwner owner;
    try {
      owner = ProfileOperationOwner(
        accessReader: _accessReader,
        profile: profile,
      );
    } on AuraProfileAccessDenied {
      return;
    }
    if (!_preferences.state.consentGranted) {
      state = const AiChatState(
        failureKind: AiFailureKind.consentRequired,
        errorMessage: 'External AI requests require your explicit consent.',
      );
      return;
    }
    final ({int generation, int lockGeneration, AiCancelToken token}) op =
        _beginGeneration();
    try {
      await _runCompletion(
        conversationId: conversationId,
        owner: owner,
        generation: op.generation,
        lockGeneration: op.lockGeneration,
        token: op.token,
      );
    } finally {
      _endGeneration(op.generation, op.token);
    }
  }

  void cancel() => _cancelToken?.cancel();

  void clearError() {
    if (state.hasError) {
      state = state.copyWith(clearError: true);
    }
  }

  /// Surfaces the fixed respectful-language warning without sending anything.
  ///
  /// The composer uses this before clearing text so a blocked message is not
  /// lost; [send] also calls it for programmatic callers.
  void showBlockedInput() {
    state = const AiChatState(
      failureKind: AiFailureKind.badRequest,
      errorMessage: AiInputPolicy.blockedMessage,
    );
  }

  void discardForLock() {
    // A private session ending invalidates every in-flight generation before
    // its next await, so stale text can never be published after the lock.
    _lockGeneration++;
    _activeGeneration = 0;
    _cancelToken?.cancel();
    _lastPrompt = null;
    state = const AiChatState();
  }

  Future<void> _runCompletion({
    required String conversationId,
    required ProfileOperationOwner owner,
    required int generation,
    required int lockGeneration,
    required AiCancelToken token,
  }) async {
    bool current() => owner.isCurrent && _isCurrent(generation, lockGeneration);

    AiProviderConfig? selected;
    try {
      selected = _selectedConfig();
    } on AiException catch (error) {
      if (!current()) return;
      state = AiChatState(
        failureKind: error.kind,
        errorMessage: error.message,
      );
      return;
    }
    if (!current() || token.isCancelled) return;
    if (selected == null) {
      state = const AiChatState(
        failureKind: AiFailureKind.needsConfiguration,
        errorMessage: 'Select an enabled, valid provider first.',
      );
      return;
    }
    final AiProviderConfig config = selected;
    final StringBuffer buffer = StringBuffer();
    final Stopwatch elapsed = Stopwatch();
    int chunks = 0;
    try {
      final String? apiKey =
          await _credentials.resolveKey(providerId: config.id);
      if (!current() || token.isCancelled) return;
      if (!_accessReader().canRead(profile)) {
        state = const AiChatState();
        return;
      }
      if (!config.isLocal && (apiKey == null || apiKey.isEmpty)) {
        state = const AiChatState(
          failureKind: AiFailureKind.missingCredentials,
          errorMessage: 'Add an API key for the selected provider first.',
        );
        return;
      }

      final AiConversation conversation = _conversations.state.firstWhere(
        (AiConversation item) => item.id == conversationId,
        orElse: () => const AiConversation(id: ''),
      );
      if (conversation.id.isEmpty) {
        state = const AiChatState(
          failureKind: AiFailureKind.unknown,
          errorMessage: 'The active conversation is no longer available.',
        );
        return;
      }

      // Context assembly is side-effect free and profile scoped. Nothing is sent
      // when the snapshot is from another profile or exceeds the safe budget.
      final AiLanguage language = _preferences.state.language;

      // Memory retrieval is caller-owned and fail-closed: the source returns
      // nothing when the workspace is locked, the profile differs, or retrieval
      // is disabled. A retrieval failure never becomes an invented memory.
      List<AiMemoryContextItem> memories = const <AiMemoryContextItem>[];
      try {
        memories = await _memorySource.retrieveRelevant(
          query: _lastPrompt?.trim() ?? '',
          now: _now(),
          limit: AuraRuntimeConfig.maxMemoryContextItems,
        );
      } catch (_) {
        memories = const <AiMemoryContextItem>[];
      }
      if (!current() || token.isCancelled) return;
      if (!_accessReader().canRead(profile)) {
        state = const AiChatState();
        return;
      }
      final Set<AiContextSource> enabledSources = <AiContextSource>{
        AiContextSource.conversationHistory,
        if (memories.isNotEmpty) AiContextSource.approvedMemory,
      };

      final AiAssembledContext assembled = _contextAssembler.assemble(
        AiContextRequest(
          profile: profile,
          historyProfile: profile,
          history: conversation.list(),
          language: language,
          enabledSources: enabledSources,
          memories: memories,
          memoryProfile: profile,
        ),
      );
      if (assembled.includedMemoryIds.isNotEmpty) {
        unawaited(
          _memorySource.markAccessed(
            assembled.includedMemoryIds.toList(growable: false),
          ),
        );
      }
      if (assembled.isEmpty) {
        state = const AiChatState(
          failureKind: AiFailureKind.payloadTooLarge,
          errorMessage:
              'The current message is unavailable or too large for the context budget.',
        );
        return;
      }
      if (!current() || token.isCancelled) return;

      elapsed.start();
      await for (final String delta in _client.streamCompletion(
        config: config,
        messages: assembled.messages,
        language: language,
        context: AiRequestContext(
          apiKey: apiKey,
          cancelToken: token,
          assembledContext: assembled,
        ),
      )) {
        if (!current() || token.isCancelled) break;
        buffer.write(delta);
        chunks++;
        state = AiChatState(isBusy: true, streamingText: buffer.toString());
      }
      // A stale generation must never publish text or clear a newer state.
      if (!current()) return;

      final String response = buffer.toString().trim();
      if (token.isCancelled) {
        // The transport may close normally after abort. Partial text must be
        // labelled interrupted, never presented as a complete answer.
        if (response.isNotEmpty) {
          _appendAssistant(
              conversationId, owner: owner, response, interrupted: true);
        }
        _recordPersist(config, AiDiagnosticOutcome.cancelled, chunks, elapsed);
        state = const AiChatState();
        return;
      }
      if (response.isEmpty) {
        _recordPersist(config, AiDiagnosticOutcome.failed, chunks, elapsed);
        state = const AiChatState(
          failureKind: AiFailureKind.malformedResponse,
          errorMessage: 'The provider returned an empty response.',
        );
        return;
      }
      _appendAssistant(
          conversationId, owner: owner, response, interrupted: false);
      _recordPersist(config, AiDiagnosticOutcome.succeeded, chunks, elapsed);
      _lastPrompt = null;
      state = const AiChatState();
    } on AiException catch (error) {
      if (!current()) return;
      final bool wasCancelled =
          token.isCancelled || error.kind == AiFailureKind.cancelled;
      final String partial = buffer.toString().trim();
      if (partial.isNotEmpty) {
        _appendAssistant(
            conversationId, owner: owner, partial, interrupted: true);
      }
      _recordPersist(
        config,
        wasCancelled
            ? AiDiagnosticOutcome.cancelled
            : AiDiagnosticOutcome.failed,
        chunks,
        elapsed,
      );
      state = wasCancelled
          ? const AiChatState()
          : AiChatState(
              failureKind: error.kind,
              errorMessage: error.message,
            );
      if (!wasCancelled) {
        _logger.warning('ai', 'Completion failed (${error.kind.name})');
      }
    } catch (_) {
      if (!current()) return;
      final String partial = buffer.toString().trim();
      if (partial.isNotEmpty) {
        _appendAssistant(
            conversationId, owner: owner, partial, interrupted: true);
      }
      _recordPersist(config, AiDiagnosticOutcome.failed, chunks, elapsed);
      state = const AiChatState(
        failureKind: AiFailureKind.unknown,
        errorMessage: 'The assistant could not complete the response.',
      );
      _logger.warning('ai', 'Completion failed with an unexpected error');
    }
  }

  void _recordPersist(
    AiProviderConfig config,
    AiDiagnosticOutcome outcome,
    int chunks,
    Stopwatch elapsed,
  ) {
    _diagnostics.record(
      AiDiagnosticEvent(
        stage: AiRequestStage.persist,
        providerId: config.id,
        host: 'local',
        method: 'N/A',
        outcome: outcome,
        durationMs: elapsed.elapsedMilliseconds,
        tokensReceived: chunks,
      ),
    );
  }

  void _appendAssistant(
    String conversationId,
    String content, {
    required ProfileOperationOwner owner,
    required bool interrupted,
  }) {
    // A lock or profile switch during streaming invalidates this result. Never
    // add it to a conversation that is no longer readable by this controller.
    if (!owner.isCurrent || !_accessReader().canRead(profile)) return;
    _conversations.appendMessage(
      conversationId,
      AiMessage(
        role: AiMessageRole.assistant,
        content: content,
        timestamp: _now(),
        isInterrupted: interrupted,
      ),
    );
  }

  AiProviderConfig? _selectedConfig() {
    // Shared with the provider cards and readiness badge so "used by the next
    // request" cannot drift from the controller's actual choice.
    final AiProviderConfig? effective =
        AiProviderSelection.effective(_configs.state, _preferences.state);
    if (effective == null) return null;
    if (effective.validate() != null) {
      throw const AiException(
        AiFailureKind.configuration,
        'The selected provider configuration is incomplete.',
      );
    }
    if (effective.isLocal && !_ollamaAvailable) {
      throw const AiException(
        AiFailureKind.unsupportedProvider,
        AiProviderManagementMessages.ollamaAndroidUnavailable,
      );
    }
    if (effective.kind == AiProviderKind.googleGemini) {
      throw const AiException(
        AiFailureKind.unsupportedProvider,
        'This provider kind is not supported yet.',
      );
    }
    return effective;
  }

  @override
  void dispose() {
    _lockGeneration++;
    _activeGeneration = 0;
    cancel();
    super.dispose();
  }
}

enum AiConnectionStatus {
  unknown,
  testing,
  connected,
  disconnected,
  needsRefresh,
  error,
}

class AiConnectionState {
  const AiConnectionState({
    this.status = AiConnectionStatus.unknown,
    this.message,
    this.testedAt,
    this.verifiedProviderId,
    this.verifiedSignature,
    this.failureKind,
  });

  final AiConnectionStatus status;
  final String? message;
  final DateTime? testedAt;
  final AiFailureKind? failureKind;

  /// Non-secret fingerprint of the exact config that was verified.
  final String? verifiedProviderId;
  final String? verifiedSignature;

  /// Verification replaces itself after this interval without a new test.
  static const Duration verificationMaxAge = Duration(minutes: 30);

  bool get isStale {
    final DateTime? tested = testedAt;
    if (tested == null) return true;
    return DateTime.now().difference(tested) > verificationMaxAge;
  }

  /// True when a previous `/models` result cannot be claimed for [config].
  bool matches(AiProviderConfig config) =>
      status == AiConnectionStatus.connected &&
      verifiedProviderId == config.id &&
      verifiedSignature == _signature(config) &&
      !isStale;

  static String _signature(AiProviderConfig config) =>
      '${config.kind.name}|${config.baseUrl.trim()}|${config.model.trim()}';

  AiConnectionState copyWith({
    AiConnectionStatus? status,
    String? message,
    DateTime? testedAt,
    String? verifiedProviderId,
    String? verifiedSignature,
    AiFailureKind? failureKind,
    bool clearMessage = false,
  }) {
    return AiConnectionState(
      status: status ?? this.status,
      message: clearMessage ? null : message ?? this.message,
      testedAt: testedAt ?? this.testedAt,
      verifiedProviderId: verifiedProviderId ?? this.verifiedProviderId,
      verifiedSignature: verifiedSignature ?? this.verifiedSignature,
      failureKind: failureKind ?? this.failureKind,
    );
  }
}

/// Performs real provider connection tests and metadata-only model discovery.
///
/// Never reports success from a saved key alone, never sends conversation
/// content, and keeps an independent status per provider so selecting one
/// workspace provider does not invent a claim about another.
class AiConnectionController extends StateNotifier<AiConnectionState> {
  AiConnectionController({
    required AiConfigController configs,
    required AiCredentialController credentials,
    required AiClient client,
    required AuraLogger logger,
    required ProfileAccessReader accessReader,
    AiProviderRouter? router,
    bool ollamaAvailable = true,
  })  : _configs = configs,
        _credentials = credentials,
        _client = client,
        _logger = logger,
        _accessReader = accessReader,
        _router = router,
        _ollamaAvailable = ollamaAvailable,
        super(const AiConnectionState());

  final AiConfigController _configs;
  final AiCredentialController _credentials;
  final AiClient _client;
  final AuraLogger _logger;
  final ProfileAccessReader _accessReader;
  final bool _ollamaAvailable;

  /// Exposed only for explicit-reader seam tests.
  ProfileAccessReader get accessReader => _accessReader;

  AuraProfile get profile => _configs.profile;

  /// Model discovery is deliberately not part of [AiClient], so it is injected
  /// separately. The plain client seam used by chat remains untouched.
  final AiProviderRouter? _router;

  final Map<String, AiConnectionState> _statusByProvider =
      <String, AiConnectionState>{};
  final Map<String, AiModelCatalogEntry> _modelsByProvider =
      <String, AiModelCatalogEntry>{};
  final Map<String, int> _testGenerations = <String, int>{};
  final Map<String, int> _modelGenerations = <String, int>{};
  // These maps are the synchronous per-provider guards. Status-based checks
  // are too late because status is only published after credential resolution;
  // independent providers deliberately remain concurrency-safe with each other.
  // The live token is the ownership identity, so cancellation can release the
  // slot immediately while identity-checked cleanup prevents an old operation
  // from releasing or overwriting a newer one.
  final Map<String, AiCancelToken> _testTokens = <String, AiCancelToken>{};
  final Map<String, AiCancelToken> _modelTokens = <String, AiCancelToken>{};
  String? _activeProviderId;
  int _lockGeneration = 0;

  bool _canRead() => _accessReader().canRead(profile);

  void _requirePrivate() {
    _accessReader().requirePrivate(profile, true);
  }

  /// Status of one provider card. Unverified providers stay truthfully unknown.
  ///
  /// A locked private workspace sees only the neutral idle state.
  AiConnectionState statusFor(String providerId) {
    if (!_canRead()) return const AiConnectionState();
    return _statusByProvider[providerId] ?? const AiConnectionState();
  }

  /// Bounded model metadata for one provider card.
  AiModelCatalogEntry modelsFor(String providerId) {
    if (!_canRead()) return const AiModelCatalogEntry();
    return _modelsByProvider[providerId] ?? const AiModelCatalogEntry();
  }

  AiProviderConfig _configOrEmpty(String providerId) =>
      AiProviderSelection.byId(_configs.state, providerId) ??
      const AiProviderConfig(
        id: '',
        label: '',
        kind: AiProviderKind.openAiCompatible,
        baseUrl: '',
        model: '',
      );

  bool _isStale(
    String providerId,
    int generation,
    int lockGeneration, {
    ProfileOperationOwner? owner,
  }) =>
      (owner != null && !owner.isCurrent) ||
      lockGeneration != _lockGeneration ||
      generation != _testGenerations[providerId];

  bool _isModelStale(
    String providerId,
    int generation,
    int lockGeneration, {
    ProfileOperationOwner? owner,
  }) =>
      (owner != null && !owner.isCurrent) ||
      lockGeneration != _lockGeneration ||
      generation != _modelGenerations[providerId];

  void _publishCancelledTest(String providerId) {
    _apply(
      providerId,
      AiConnectionState(
        status: AiConnectionStatus.error,
        message: AiProviderManagementMessages.cancelled,
        testedAt: DateTime.now(),
        failureKind: AiFailureKind.cancelled,
      ),
    );
  }

  void _publishCancelledModels(String providerId) {
    _modelsByProvider[providerId] = const AiModelCatalogEntry(
      status: AiModelLoadStatus.error,
      failureKind: AiFailureKind.cancelled,
      message: AiProviderManagementMessages.cancelled,
    );
  }

  /// Cancels and releases one test slot. Advancing the generation here is what
  /// makes the old operation stale before a retry can acquire the slot.
  bool _releaseTestOwnership(
    String providerId, {
    required bool publishCancelled,
  }) {
    final AiCancelToken? token = _testTokens.remove(providerId);
    if (token == null) return false;
    token.cancel();
    _testGenerations[providerId] = (_testGenerations[providerId] ?? 0) + 1;
    if (publishCancelled) _publishCancelledTest(providerId);
    return true;
  }

  /// Cancels and releases one discovery slot with the same ownership rules.
  bool _releaseModelOwnership(
    String providerId, {
    required bool publishCancelled,
  }) {
    final AiCancelToken? token = _modelTokens.remove(providerId);
    if (token == null) return false;
    token.cancel();
    _modelGenerations[providerId] = (_modelGenerations[providerId] ?? 0) + 1;
    if (publishCancelled) _publishCancelledModels(providerId);
    return true;
  }

  /// Keeps the legacy single-provider state in sync while exposing per-provider
  /// status. Results for a provider that is not the active one never overwrite
  /// the active provider's badge.
  void _apply(String providerId, AiConnectionState next) {
    _statusByProvider[providerId] = next;
    if (_activeProviderId == providerId ||
        state.verifiedProviderId == providerId) {
      state = next;
    }
  }

  Future<void> test({required String providerId}) async {
    _requirePrivate();
    final ProfileOperationOwner owner = ProfileOperationOwner(
      accessReader: _accessReader,
      profile: profile,
    );
    if (_testTokens.containsKey(providerId)) return;
    final AiCancelToken token = AiCancelToken();
    _testTokens[providerId] = token;
    int? generation;
    int? lockGeneration;
    try {
      final AiProviderConfig config = _configOrEmpty(providerId);
      if (config.id.isEmpty || config.validateEndpoint() != null) {
        _apply(
          providerId,
          const AiConnectionState(
            status: AiConnectionStatus.error,
            message: 'Complete the provider configuration before testing.',
          ),
        );
        return;
      }
      if (config.isLocal && !_ollamaAvailable) {
        _apply(
          providerId,
          AiConnectionState(
            status: AiConnectionStatus.error,
            message: AiProviderManagementMessages.ollamaAndroidUnavailable,
            testedAt: DateTime.now(),
            failureKind: AiFailureKind.unsupportedProvider,
          ),
        );
        return;
      }

      // Ownership is established before the credential await so a second test
      // cannot replace this token and cancellation reaches a blocked probe.
      generation = (_testGenerations[providerId] ?? 0) + 1;
      _testGenerations[providerId] = generation;
      lockGeneration = _lockGeneration;
      _activeProviderId = providerId;
      _apply(providerId,
          const AiConnectionState(status: AiConnectionStatus.testing));

      final String? apiKey =
          await _credentials.resolveKey(providerId: providerId);
      if (_isStale(providerId, generation, lockGeneration, owner: owner)) {
        return;
      }
      if (token.isCancelled) {
        _publishCancelledTest(providerId);
        return;
      }
      if (!config.isLocal && (apiKey == null || apiKey.isEmpty)) {
        _apply(
          providerId,
          const AiConnectionState(
            status: AiConnectionStatus.error,
            message: 'Add an API key before testing this provider.',
          ),
        );
        return;
      }

      await _client.testConnection(
        config: config,
        context: AiRequestContext(
          apiKey: apiKey,
          cancelToken: token,
          timeout: const Duration(seconds: 20),
        ),
      );
      if (_isStale(providerId, generation, lockGeneration, owner: owner)) {
        return;
      }
      // Defensive: a cancel can land after the adapter's last token check but
      // before this line. Never publish success for a cancelled operation.
      if (token.isCancelled) {
        _publishCancelledTest(providerId);
        return;
      }
      _apply(
        providerId,
        AiConnectionState(
          status: AiConnectionStatus.connected,
          message: config.isLocal
              ? 'Local provider endpoint reachable.'
              : 'Metadata access verified with /models.',
          testedAt: DateTime.now(),
          verifiedProviderId: config.id,
          verifiedSignature: AiConnectionState._signature(config),
        ),
      );
      _logger.info('ai', 'Provider metadata test succeeded.');
    } on AiException catch (error) {
      // Cancellation publishes its own terminal state and advances the
      // generation, so an old operation can never publish here.
      if (generation == null ||
          lockGeneration == null ||
          _isStale(providerId, generation, lockGeneration, owner: owner)) {
        return;
      }
      _apply(
        providerId,
        AiConnectionState(
          status: AiConnectionStatus.error,
          message: error.message,
          testedAt: DateTime.now(),
          failureKind: error.kind,
        ),
      );
      _logger.warning(
          'ai', 'Provider connection test failed (${error.kind.name})');
    } catch (_) {
      if (generation == null ||
          lockGeneration == null ||
          _isStale(providerId, generation, lockGeneration, owner: owner)) {
        return;
      }
      if (token.isCancelled) {
        _publishCancelledTest(providerId);
        return;
      }
      _apply(
        providerId,
        const AiConnectionState(
          status: AiConnectionStatus.error,
          message: 'The connection test could not be completed.',
        ),
      );
    } finally {
      if (identical(_testTokens[providerId], token)) {
        _testTokens.remove(providerId);
      }
    }
  }

  /// Requests provider model metadata only. No messages, prompts, transcripts,
  /// memory or credentials are included beyond the transient request key.
  Future<void> refreshModels({required String providerId}) async {
    _requirePrivate();
    await discoverModels(_configOrEmpty(providerId));
  }

  /// Same probe for a configuration that has not been saved yet. Used by the
  /// setup form so an Ollama model can be chosen before the first save.
  Future<void> discoverModels(AiProviderConfig config) async {
    _requirePrivate();
    final ProfileOperationOwner owner = ProfileOperationOwner(
      accessReader: _accessReader,
      profile: profile,
    );
    final String providerId = config.id;
    if (_modelTokens.containsKey(providerId)) return;
    final AiCancelToken token = AiCancelToken();
    _modelTokens[providerId] = token;
    int? generation;
    int? lockGeneration;
    try {
      if (config.id.isEmpty || config.kind == AiProviderKind.googleGemini) {
        _modelsByProvider[providerId] = const AiModelCatalogEntry(
          status: AiModelLoadStatus.error,
          message: AiProviderManagementMessages.unsupported,
        );
        return;
      }
      if (config.isLocal && !_ollamaAvailable) {
        _modelsByProvider[providerId] = const AiModelCatalogEntry(
          status: AiModelLoadStatus.error,
          failureKind: AiFailureKind.unsupportedProvider,
          message: AiProviderManagementMessages.ollamaAndroidUnavailable,
        );
        return;
      }
      final String? endpointError = config.validateEndpoint();
      if (endpointError != null) {
        _modelsByProvider[providerId] = const AiModelCatalogEntry(
          status: AiModelLoadStatus.error,
          message: AiProviderManagementMessages.configuration,
        );
        return;
      }
      final AiProviderRouter? router = _router;
      if (router == null) {
        _modelsByProvider[providerId] = const AiModelCatalogEntry(
          status: AiModelLoadStatus.error,
          message: AiProviderManagementMessages.discoveryUnavailable,
        );
        return;
      }

      // Ownership precedes the credential await. A duplicate request returns
      // immediately and cannot replace this operation's token or generation.
      generation = (_modelGenerations[providerId] ?? 0) + 1;
      _modelGenerations[providerId] = generation;
      lockGeneration = _lockGeneration;
      _modelsByProvider[providerId] =
          const AiModelCatalogEntry(status: AiModelLoadStatus.loading);

      final String? apiKey =
          await _credentials.resolveKey(providerId: providerId);
      if (_isModelStale(providerId, generation, lockGeneration, owner: owner)) {
        return;
      }
      if (token.isCancelled) {
        _publishCancelledModels(providerId);
        return;
      }
      if (!config.isLocal && (apiKey == null || apiKey.isEmpty)) {
        _modelsByProvider[providerId] = const AiModelCatalogEntry(
          status: AiModelLoadStatus.error,
          message: AiProviderManagementMessages.credentials,
        );
        return;
      }

      final List<AiModelInfo> models = await router.listModels(
        config: config,
        context: AiRequestContext(
          apiKey: apiKey,
          cancelToken: token,
          timeout: const Duration(seconds: 20),
        ),
      );
      if (_isModelStale(providerId, generation, lockGeneration, owner: owner)) {
        return;
      }
      // Defensive: a cancel can land after the adapter's last token check but
      // before publish. Never present stale metadata for a cancelled request.
      if (token.isCancelled) {
        _publishCancelledModels(providerId);
        return;
      }
      final String selected = config.model.trim();
      final bool noModels = models.isEmpty;
      final bool selectedMissing = selected.isNotEmpty &&
          !models.any((AiModelInfo model) => model.id == selected);
      final String? message = noModels
          ? selectedMissing
              ? '${AiProviderManagementMessages.noModels} '
                  '${AiProviderManagementMessages.selectedModelMissing}'
              : AiProviderManagementMessages.noModels
          : selectedMissing
              ? AiProviderManagementMessages.selectedModelMissing
              : null;
      _modelsByProvider[providerId] = AiModelCatalogEntry(
        status:
            noModels ? AiModelLoadStatus.noModels : AiModelLoadStatus.loaded,
        models: models,
        message: message,
        loadedAt: DateTime.now(),
      );
    } on AiException catch (error) {
      if (generation == null || lockGeneration == null) return;
      // Cancellation publishes its own terminal state and advances the
      // generation, so an old request can never publish here. The captured
      // lock generation must be used: comparing the current value would make
      // the lock check inert and let a stale error overwrite a newer request.
      if (_isModelStale(providerId, generation, lockGeneration, owner: owner)) {
        return;
      }
      final bool offline =
          AiProviderManagementMessages.isConnectionFailure(error.kind);
      _modelsByProvider[providerId] = AiModelCatalogEntry(
        status:
            offline ? AiModelLoadStatus.unavailable : AiModelLoadStatus.error,
        failureKind: error.kind,
        message: config.isLocal && offline
            ? AiProviderManagementMessages.ollamaOffline
            : AiProviderManagementMessages.forFailure(error.kind),
      );
      _logger.warning('ai', 'Model discovery failed (${error.kind.name})');
    } catch (_) {
      if (generation == null ||
          lockGeneration == null ||
          _isModelStale(providerId, generation, lockGeneration, owner: owner)) {
        return;
      }
      if (token.isCancelled) {
        _publishCancelledModels(providerId);
        return;
      }
      _modelsByProvider[providerId] = const AiModelCatalogEntry(
        status: AiModelLoadStatus.error,
        message: AiProviderManagementMessages.unknown,
      );
    } finally {
      if (identical(_modelTokens[providerId], token)) {
        _modelTokens.remove(providerId);
      }
    }
  }

  void _cancelAllTokens() {
    for (final AiCancelToken token in _testTokens.values) {
      token.cancel();
    }
    for (final AiCancelToken token in _modelTokens.values) {
      token.cancel();
    }
  }

  void cancel({String? providerId}) {
    _requirePrivate();
    if (providerId != null) {
      _releaseTestOwnership(providerId, publishCancelled: true);
      _releaseModelOwnership(providerId, publishCancelled: true);
      return;
    }
    for (final String id in _testTokens.keys.toList()) {
      _releaseTestOwnership(id, publishCancelled: true);
    }
    for (final String id in _modelTokens.keys.toList()) {
      _releaseModelOwnership(id, publishCancelled: true);
    }
  }

  void markDisconnected({String? providerId}) {
    _requirePrivate();
    final String? id = providerId ?? _activeProviderId;
    if (id == null) return;
    _apply(
        id, const AiConnectionState(status: AiConnectionStatus.disconnected));
  }

  /// Called when configuration, selection or credentials change. A previous
  /// `/models` result must not be presented as valid for the new setup.
  void invalidate({String? providerId}) {
    _requirePrivate();
    final String? id = providerId ?? _activeProviderId;
    if (id == null) return;
    // A configuration or provider change makes an in-flight probe's eventual
    // answer irrelevant. Release ownership immediately so a retry is not held
    // hostage by a transport that never completes; the generation advances with
    // that release and makes the old operation stale before touching status.
    _releaseTestOwnership(id, publishCancelled: false);
    _releaseModelOwnership(id, publishCancelled: false);
    // The invalidated discovery can no longer publish, so its `loading` badge
    // must become terminal instead of waiting forever for a discarded result.
    final AiModelCatalogEntry currentModels =
        _modelsByProvider[id] ?? const AiModelCatalogEntry();
    if (currentModels.isLoading) {
      _modelsByProvider[id] = const AiModelCatalogEntry();
    }
    final AiConnectionState current = _statusByProvider[id] ?? state;
    if (current.status == AiConnectionStatus.connected ||
        current.status == AiConnectionStatus.needsRefresh ||
        current.status == AiConnectionStatus.testing) {
      // An invalidated in-flight test can no longer publish its result, so its
      // `testing` badge must become terminal instead of spinning forever.
      _apply(
        id,
        AiConnectionState(
          status: AiConnectionStatus.needsRefresh,
          message: 'Provider details changed. Test the connection again.',
          testedAt: current.testedAt,
        ),
      );
    }
  }

  void discardForLock() {
    // Lock-driven cleanup must remain callable while access is denied.
    _cancelAllTokens();
    _lockGeneration++;
    _testGenerations.clear();
    _modelGenerations.clear();
    _testTokens.clear();
    _modelTokens.clear();
    _statusByProvider.clear();
    _modelsByProvider.clear();
    _activeProviderId = null;
    state = const AiConnectionState();
  }

  @override
  void dispose() {
    _lockGeneration++;
    _cancelAllTokens();
    super.dispose();
  }
}

enum AiCredentialPresence { unknown, present, missing }

class AiCredentialState {
  const AiCredentialState({
    this.presence = AiCredentialPresence.unknown,
    this.failureKind,
    this.errorMessage,
  });

  final AiCredentialPresence presence;

  /// Typed, secret-free credential-vault failure for the last management action.
  final AiFailureKind? failureKind;
  final String? errorMessage;

  bool get hasError => errorMessage != null;

  AiCredentialState copyWith({
    AiCredentialPresence? presence,
    AiFailureKind? failureKind,
    String? errorMessage,
    bool clearError = false,
  }) {
    return AiCredentialState(
      presence: presence ?? this.presence,
      failureKind: clearError ? null : (failureKind ?? this.failureKind),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Tracks only credential presence and safe failure metadata.
/// The raw key never enters Riverpod state.
class AiCredentialController extends StateNotifier<AiCredentialState> {
  AiCredentialController({
    required this.profile,
    required AiCredentialStore store,
    required ProfileAccessReader accessReader,
    AiDiagnostics? diagnostics,
  })  : _store = store,
        _accessReader = accessReader,
        _diagnostics = diagnostics ?? const NoAiDiagnostics(),
        super(const AiCredentialState()) {
    refresh();
  }

  final AuraProfile profile;
  final AiCredentialStore _store;
  final ProfileAccessReader _accessReader;
  final AiDiagnostics _diagnostics;
  int _generation = 0;

  /// Exposed only for explicit-reader seam tests.
  ProfileAccessReader get accessReader => _accessReader;

  bool _canRead() => _accessReader().canRead(profile);

  ProfileOperationOwner _newOwner() => ProfileOperationOwner(
        accessReader: _accessReader,
        profile: profile,
      );

  bool _isCurrent(ProfileOperationOwner owner, int generation) =>
      owner.isCurrent && generation == _generation;

  void _recordCredential(
    String providerId, {
    required bool succeeded,
    AiException? failure,
  }) {
    _diagnostics.record(
      AiDiagnosticEvent(
        stage: AiRequestStage.prepare,
        providerId: providerId,
        host: 'local',
        method: 'N/A',
        outcome: succeeded
            ? AiDiagnosticOutcome.succeeded
            : AiDiagnosticOutcome.failed,
        failureKind: failure?.kind,
        exceptionType: failure?.exceptionType,
      ),
    );
  }

  AiCredentialState _failureState(AiException failure) => AiCredentialState(
        presence: state.presence,
        failureKind: failure.kind,
        errorMessage: failure.message,
      );

  Future<void> refresh({String? providerId}) async {
    if (providerId == null || !_canRead()) {
      // Never interrogate the vault while the private workspace is locked.
      state = const AiCredentialState();
      return;
    }
    final int generation = _generation;
    final ProfileOperationOwner owner = _newOwner();
    try {
      final bool hasKey = await _store.has(
        profileScope: profile.storageScope,
        providerId: providerId,
      );
      if (!_isCurrent(owner, generation)) return;
      state = AiCredentialState(
        presence: hasKey
            ? AiCredentialPresence.present
            : AiCredentialPresence.missing,
      );
      _recordCredential(providerId, succeeded: true);
    } on AiException catch (error) {
      if (!_isCurrent(owner, generation)) return;
      state = _failureState(error);
      _recordCredential(providerId, succeeded: false, failure: error);
    }
  }

  Future<void> save({
    required String providerId,
    required String apiKey,
  }) async {
    final int generation = _generation;
    final ProfileOperationOwner owner = _newOwner();
    try {
      await _store.save(
        profileScope: profile.storageScope,
        providerId: providerId,
        apiKey: apiKey,
        isWriteAllowed: () => _isCurrent(owner, generation),
      );
      if (!_isCurrent(owner, generation)) return;
      state = const AiCredentialState(
        presence: AiCredentialPresence.present,
      );
      _recordCredential(providerId, succeeded: true);
    } on AiException catch (error) {
      if (!_isCurrent(owner, generation)) return;
      state = _failureState(error);
      _recordCredential(providerId, succeeded: false, failure: error);
      rethrow;
    }
  }

  Future<void> delete({required String providerId}) async {
    final int generation = _generation;
    final ProfileOperationOwner owner = _newOwner();
    try {
      await _store.delete(
        profileScope: profile.storageScope,
        providerId: providerId,
        isWriteAllowed: () => _isCurrent(owner, generation),
      );
      if (!_isCurrent(owner, generation)) return;
      state = const AiCredentialState(
        presence: AiCredentialPresence.missing,
      );
      _recordCredential(providerId, succeeded: true);
    } on AiException catch (error) {
      if (!_isCurrent(owner, generation)) return;
      state = _failureState(error);
      _recordCredential(providerId, succeeded: false, failure: error);
      rethrow;
    }
  }

  /// Transient request-time resolution; never store this in state or logs.
  Future<String?> resolveKey({required String providerId}) async {
    final int generation = _generation;
    final ProfileOperationOwner owner = _newOwner();
    final String? key = await _store.readSecret(
      profileScope: profile.storageScope,
      providerId: providerId,
    );
    if (!_isCurrent(owner, generation)) return null;
    return key;
  }

  void discardForLock() {
    _generation++;
    state = const AiCredentialState();
  }
}

/// Forwards redacted AI lifecycle events into the existing AURA structured
/// logger. No second logging framework is introduced.
class AuraAiDiagnostics extends AiDiagnostics {
  const AuraAiDiagnostics(this._logger);

  final AuraLogger _logger;

  @override
  void record(AiDiagnosticEvent event) {
    _logger.log(
      event.outcome == AiDiagnosticOutcome.failed
          ? AuraLogLevel.warning
          : AuraLogLevel.debug,
      'ai.request',
      'AI ${event.stage.name} ${event.outcome.name}.',
      context: event.context,
    );
  }
}

// ---------------------------------------------------------------------------
// Store / client boundaries
// ---------------------------------------------------------------------------

/// Platform-gated credential store. Unsupported builds receive a fail-closed
/// store that reports no key and refuses writes, not a plaintext fallback.
final Provider<AiCredentialStore> aiCredentialStoreProvider =
    Provider<AiCredentialStore>((Ref ref) {
  if (!ref.watch(credentialVaultAvailableProvider)) {
    return AiCredentialStore.unavailable();
  }
  return AiCredentialStore();
});

final Provider<AiDiagnostics> aiDiagnosticsProvider = Provider<AiDiagnostics>(
  (Ref ref) => AuraAiDiagnostics(ref.read(auraLoggerProvider.notifier)),
);

/// Adapter registry. Adding a provider means registering an adapter here, not
/// changing chat controllers. No credential or conversation data is stored.
final Provider<AiProviderRegistry> aiProviderRegistryProvider =
    Provider<AiProviderRegistry>((Ref ref) {
  final bool ollamaAvailable = ref.watch(localOllamaAvailableProvider);
  final List<AiProviderAdapter> adapters = <AiProviderAdapter>[
    OpenAiCompatibleAiClient(
      transport: const DartIoAiHttpTransport(),
      diagnostics: ref.read(aiDiagnosticsProvider),
    ),
  ];
  if (ollamaAvailable) {
    adapters.add(
      OllamaAiAdapter(
        transport: const DartIoAiHttpTransport(),
        diagnostics: ref.read(aiDiagnosticsProvider),
      ),
    );
  }
  return DefaultAiProviderRegistry(adapters);
});

/// Typed routing boundary for future model discovery and provider management.
final Provider<AiProviderRouter> aiProviderRouterProvider =
    Provider<AiProviderRouter>(
  (Ref ref) => AiProviderRouter(
    registry: ref.read(aiProviderRegistryProvider),
  ),
);

/// Controllers keep the unchanged [AiClient] seam; routing is an implementation
/// detail behind it.
final Provider<AiClient> aiClientProvider = Provider<AiClient>(
  (Ref ref) => ref.read(aiProviderRouterProvider),
);

/// Stateless context assembler. Profile isolation is enforced from the
/// [AiContextRequest] supplied by the profile-scoped chat controller.
final Provider<AiContextAssembler> aiContextAssemblerProvider =
    Provider<AiContextAssembler>(
  (Ref ref) => const DefaultAiContextAssembler(),
);

final ProviderFamily<AiConfigStore, AuraProfile> aiConfigStoreForProvider =
    ProviderFamily<AiConfigStore, AuraProfile>(
  (Ref ref, AuraProfile profile) => AiConfigStore(profile: profile),
);

final ProviderFamily<AiPreferencesStore, AuraProfile>
    aiPreferencesStoreForProvider =
    ProviderFamily<AiPreferencesStore, AuraProfile>(
  (Ref ref, AuraProfile profile) => AiPreferencesStore(profile: profile),
);

/// Selects the storage backend for one profile.
///
/// FAMILY keeps its unchanged versioned plaintext JSON. AYUSH uses a separate
/// DPAPI-encrypted file; the repository, controllers and UI are unaware of the
/// difference. The legacy AYUSH plaintext file is never deleted here: it is
/// migrated by [EncryptedAiConversationStore] on first authenticated read.
final ProviderFamily<AiConversationStorage, AuraProfile>
    aiConversationStorageForProvider =
    ProviderFamily<AiConversationStorage, AuraProfile>(
  (Ref ref, AuraProfile profile) {
    _guardProfile(ref, profile);
    if (profile == AuraProfile.ayush) {
      return EncryptedAiConversationStore(
        profile: profile,
        cipher: ref.read(ayushConversationCipherProvider),
        isWriteAllowed: () => ref.read(profileAccessProvider).canRead(profile),
      );
    }
    return AiConversationStore(profile: profile);
  },
);

final ProviderFamily<AiConversationRepository, AuraProfile>
    aiConversationRepositoryForProvider =
    ProviderFamily<AiConversationRepository, AuraProfile>(
  (Ref ref, AuraProfile profile) {
    _guardProfile(ref, profile);
    return ProfileBoundAiConversationRepository(
      profile: profile,
      storage: ref.read(aiConversationStorageForProvider(profile)),
      accessReader: () => ref.read(profileAccessProvider),
    );
  },
);

// ---------------------------------------------------------------------------
// Profile-scoped controllers
// ---------------------------------------------------------------------------

void _guardProfile(Ref ref, AuraProfile profile) {
  ref.read(profileAccessProvider).requirePrivate(profile, true);
}

void _watchLock(Ref ref, AuraProfile profile, void Function() onLocked,
    {void Function()? onUnlocked}) {
  ref.listen<ProfileSession>(profileSessionProvider, (_, ProfileSession next) {
    if (ProfileAccess(next).canRead(profile)) {
      onUnlocked?.call();
    } else {
      onLocked();
    }
  });
}

final StateNotifierProviderFamily<AiConfigController, List<AiProviderConfig>,
        AuraProfile> aiConfigsForProvider =
    StateNotifierProvider.family<AiConfigController, List<AiProviderConfig>,
        AuraProfile>((Ref ref, AuraProfile profile) {
  _guardProfile(ref, profile);
  final AiConfigController controller = AiConfigController(
    profile: profile,
    store: ref.read(aiConfigStoreForProvider(profile)),
    logger: ref.read(auraLoggerProvider.notifier),
    accessReader: () => ref.read(profileAccessProvider),
  );
  _watchLock(
    ref,
    profile,
    controller.discardForLock,
    onUnlocked: controller.load,
  );
  return controller;
});

final StateNotifierProviderFamily<AiPreferencesController, AiPreferences,
        AuraProfile> aiPreferencesForProvider =
    StateNotifierProvider.family<AiPreferencesController, AiPreferences,
        AuraProfile>((Ref ref, AuraProfile profile) {
  _guardProfile(ref, profile);
  final AiPreferencesController controller = AiPreferencesController(
    profile: profile,
    store: ref.read(aiPreferencesStoreForProvider(profile)),
    accessReader: () => ref.read(profileAccessProvider),
  );
  _watchLock(
    ref,
    profile,
    controller.discardForLock,
    onUnlocked: controller.load,
  );
  return controller;
});

final StateNotifierProviderFamily<AiConversationLibraryController,
        List<AiConversation>, AuraProfile> aiConversationsForProvider =
    StateNotifierProvider.family<AiConversationLibraryController,
        List<AiConversation>, AuraProfile>((Ref ref, AuraProfile profile) {
  _guardProfile(ref, profile);
  final AiConversationLibraryController controller =
      AiConversationLibraryController(
    profile: profile,
    repository: ref.read(aiConversationRepositoryForProvider(profile)),
    accessReader: () => ref.read(profileAccessProvider),
  );
  _watchLock(
    ref,
    profile,
    controller.discardForLock,
    onUnlocked: controller.load,
  );
  return controller;
});

final StateNotifierProviderFamily<AiCredentialController, AiCredentialState,
        AuraProfile> aiCredentialsForProvider =
    StateNotifierProvider.family<AiCredentialController, AiCredentialState,
        AuraProfile>((Ref ref, AuraProfile profile) {
  _guardProfile(ref, profile);
  final AiCredentialController controller = AiCredentialController(
    profile: profile,
    store: ref.read(aiCredentialStoreProvider),
    accessReader: () => ref.read(profileAccessProvider),
    diagnostics: ref.read(aiDiagnosticsProvider),
  );
  _watchLock(
    ref,
    profile,
    controller.discardForLock,
    onUnlocked: () {
      // Presence is refreshed when a provider is selected; avoid reading the
      // OS vault for every profile switch.
    },
  );
  return controller;
});

final StateNotifierProviderFamily<AiChatController, AiChatState, AuraProfile>
    aiChatForProvider =
    StateNotifierProvider.family<AiChatController, AiChatState, AuraProfile>(
  (Ref ref, AuraProfile profile) {
    _guardProfile(ref, profile);
    final AiChatController controller = AiChatController(
      profile: profile,
      access: ref.read(profileAccessProvider),
      accessReader: () => ref.read(profileAccessProvider),
      configs: ref.read(aiConfigsForProvider(profile).notifier),
      preferences: ref.read(aiPreferencesForProvider(profile).notifier),
      conversations: ref.read(aiConversationsForProvider(profile).notifier),
      credentials: ref.read(aiCredentialsForProvider(profile).notifier),
      client: ref.read(aiClientProvider),
      logger: ref.read(auraLoggerProvider.notifier),
      diagnostics: ref.read(aiDiagnosticsProvider),
      contextAssembler: ref.read(aiContextAssemblerProvider),
      memorySource: ref.read(memoryAiSourceForProvider(profile)),
      ollamaAvailable: ref.read(localOllamaAvailableProvider),
    );
    _watchLock(ref, profile, controller.discardForLock);
    return controller;
  },
);

final StateNotifierProviderFamily<AiConnectionController, AiConnectionState,
        AuraProfile> aiConnectionForProvider =
    StateNotifierProvider.family<AiConnectionController, AiConnectionState,
        AuraProfile>((Ref ref, AuraProfile profile) {
  _guardProfile(ref, profile);
  final AiConnectionController controller = AiConnectionController(
    configs: ref.read(aiConfigsForProvider(profile).notifier),
    credentials: ref.read(aiCredentialsForProvider(profile).notifier),
    client: ref.read(aiClientProvider),
    logger: ref.read(auraLoggerProvider.notifier),
    accessReader: () => ref.read(profileAccessProvider),
    router: ref.read(aiProviderRouterProvider),
    ollamaAvailable: ref.read(localOllamaAvailableProvider),
  );
  _watchLock(ref, profile, controller.discardForLock);
  return controller;
});

/// The single, testable sequence for changing the active provider.
///
/// Switching never clears history or changes the active conversation. If a
/// generation is running, the existing chat cancellation token is used so a
/// partial response cannot be mixed with a response from the new provider.
class AiProviderSwitchCoordinator {
  const AiProviderSwitchCoordinator({
    required this.chat,
    required this.preferences,
    required this.connection,
    required this.credentials,
  });

  final AiChatController chat;
  final AiPreferencesController preferences;
  final AiConnectionController connection;
  final AiCredentialController credentials;

  Future<void> switchTo(String? providerId) async {
    if (chat.isBusy) chat.cancel();
    await preferences.selectProvider(providerId);
    if (providerId == null) return;
    connection.invalidate(providerId: providerId);
    await credentials.refresh(providerId: providerId);
  }
}

// ---------------------------------------------------------------------------
// Active-profile views
// ---------------------------------------------------------------------------

final Provider<AiConfigController> activeAiConfigsControllerProvider =
    Provider<AiConfigController>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiConfigsForProvider(profile).notifier);
});

final Provider<List<AiProviderConfig>> activeAiConfigsProvider =
    Provider<List<AiProviderConfig>>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiConfigsForProvider(profile));
});

final Provider<AiPreferencesController> activeAiPreferencesControllerProvider =
    Provider<AiPreferencesController>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiPreferencesForProvider(profile).notifier);
});

final Provider<AiPreferences> activeAiPreferencesProvider =
    Provider<AiPreferences>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiPreferencesForProvider(profile));
});

final Provider<AiLanguage> aiLanguageProvider = Provider<AiLanguage>((Ref ref) {
  return ref.watch(activeAiPreferencesProvider).language;
});

final Provider<AiConversationLibraryController>
    activeAiConversationsControllerProvider =
    Provider<AiConversationLibraryController>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiConversationsForProvider(profile).notifier);
});

final Provider<List<AiConversation>> activeAiConversationsProvider =
    Provider<List<AiConversation>>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiConversationsForProvider(profile));
});

final Provider<AiChatController> activeAiChatControllerProvider =
    Provider<AiChatController>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiChatForProvider(profile).notifier);
});

final Provider<AiChatState> activeAiChatStateProvider =
    Provider<AiChatState>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiChatForProvider(profile));
});

/// Chat status is intentionally separate from provider verification.
final Provider<AiChatStatus> activeAiChatStatusProvider =
    Provider<AiChatStatus>((Ref ref) {
  final AiChatState chat = ref.watch(activeAiChatStateProvider);
  if (chat.isBusy) return AiChatStatus.running;
  if (chat.hasError) return AiChatStatus.failed;
  return AiChatStatus.idle;
});

final Provider<AiCredentialController> activeAiCredentialControllerProvider =
    Provider<AiCredentialController>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiCredentialsForProvider(profile).notifier);
});

final Provider<AiCredentialState> activeAiCredentialStateProvider =
    Provider<AiCredentialState>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiCredentialsForProvider(profile));
});

final Provider<AiConnectionController> activeAiConnectionControllerProvider =
    Provider<AiConnectionController>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiConnectionForProvider(profile).notifier);
});

final Provider<AiConnectionState> activeAiConnectionStateProvider =
    Provider<AiConnectionState>((Ref ref) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  return ref.watch(aiConnectionForProvider(profile));
});

final Provider<AiProviderSwitchCoordinator>
    activeAiProviderSwitchCoordinatorProvider =
    Provider<AiProviderSwitchCoordinator>((Ref ref) {
  return AiProviderSwitchCoordinator(
    chat: ref.watch(activeAiChatControllerProvider),
    preferences: ref.watch(activeAiPreferencesControllerProvider),
    connection: ref.watch(activeAiConnectionControllerProvider),
    credentials: ref.watch(activeAiCredentialControllerProvider),
  );
});

/// Per-provider connection status for the provider cards. A provider is never
/// shown as connected because another provider passed a test.
final ProviderFamily<AiConnectionState, String>
    activeAiConnectionStatusForProvider =
    ProviderFamily<AiConnectionState, String>((Ref ref, String providerId) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  final AiConnectionController controller =
      ref.watch(aiConnectionForProvider(profile).notifier);
  ref.watch(aiConnectionForProvider(profile));
  return controller.statusFor(providerId);
});

/// Bounded, non-secret model metadata for one provider card.
final ProviderFamily<AiModelCatalogEntry, String> activeAiModelsForProvider =
    ProviderFamily<AiModelCatalogEntry, String>((Ref ref, String providerId) {
  final AuraProfile profile = ref.watch(activeProfileProvider);
  final AiConnectionController controller =
      ref.watch(aiConnectionForProvider(profile).notifier);
  ref.watch(aiConnectionForProvider(profile));
  return controller.modelsFor(providerId);
});

/// The exact config the next chat request will use, or null when requests are
/// blocked. Shares the chat controller's selection rules.
final Provider<AiProviderConfig?> activeAiRequestConfigProvider =
    Provider<AiProviderConfig?>((Ref ref) {
  final bool ollamaAvailable = ref.watch(localOllamaAvailableProvider);
  final AiProviderConfig? effective = AiProviderSelection.effective(
    ref.watch(activeAiConfigsProvider),
    ref.watch(activeAiPreferencesProvider),
  );
  if (effective != null && effective.isLocal && !ollamaAvailable) return null;
  return effective;
});

final Provider<AiReadiness> aiReadinessProvider =
    Provider<AiReadiness>((Ref ref) {
  final List<AiProviderConfig> configs = ref.watch(activeAiConfigsProvider);
  final AiPreferences preferences = ref.watch(activeAiPreferencesProvider);
  final AiCredentialState credentials =
      ref.watch(activeAiCredentialStateProvider);
  final AiConnectionState connection =
      ref.watch(activeAiConnectionStateProvider);
  final bool ollamaAvailable = ref.watch(localOllamaAvailableProvider);

  if (configs.isEmpty) return AiReadiness.unconfigured;
  if (configs.every((AiProviderConfig item) => !item.enabled) ||
      configs.every((AiProviderConfig item) => !item.isValid)) {
    return AiReadiness.needsConfiguration;
  }

  const AiProviderConfig emptyConfig = AiProviderConfig(
    id: '',
    label: '',
    kind: AiProviderKind.openAiCompatible,
    baseUrl: '',
    model: '',
  );
  final String? selectedId = preferences.selectedProviderId;
  final AiProviderConfig selected = selectedId == null
      ? emptyConfig
      : configs.firstWhere(
          (AiProviderConfig item) => item.id == selectedId,
          orElse: () => emptyConfig,
        );
  final AiProviderConfig effective = selected.id.isEmpty
      ? configs.firstWhere(
          (AiProviderConfig item) => item.enabled,
          orElse: () => emptyConfig,
        )
      : selected;
  if (effective.id.isEmpty) return AiReadiness.needsConfiguration;
  if (effective.isLocal && !ollamaAvailable) return AiReadiness.unavailable;

  if (effective.isLocal) {
    if (connection.status == AiConnectionStatus.connected &&
        !connection.matches(effective)) {
      return AiReadiness.needsRefresh;
    }
    return connection.status == AiConnectionStatus.connected
        ? AiReadiness.connected
        : AiReadiness.disconnected;
  }
  if (credentials.presence == AiCredentialPresence.missing) {
    return AiReadiness.needsCredential;
  }
  switch (connection.status) {
    case AiConnectionStatus.connected:
      return connection.matches(effective)
          ? AiReadiness.connected
          : AiReadiness.needsRefresh;
    case AiConnectionStatus.needsRefresh:
      return AiReadiness.needsRefresh;
    case AiConnectionStatus.error:
      return AiReadiness.error;
    case AiConnectionStatus.testing:
    case AiConnectionStatus.disconnected:
    case AiConnectionStatus.unknown:
      return AiReadiness.disconnected;
  }
});
