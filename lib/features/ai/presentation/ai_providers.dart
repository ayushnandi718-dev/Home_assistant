import 'dart:async';
import 'dart:math';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/ai_preferences_store.dart';
import 'package:aura_hub/features/ai/data/default_ai_context_assembler.dart';
import 'package:aura_hub/features/ai/data/openai_compatible_client.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_context.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_diagnostics.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
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
  })  : _profile = profile,
        _store = store ?? AiConfigStore(profile: profile),
        _logger = logger ?? AuraLogger(),
        super(const <AiProviderConfig>[]) {
    unawaited(load());
  }

  final AuraProfile _profile;
  final AiConfigStore _store;
  final AuraLogger _logger;

  Future<void> load() async => state = await _store.load();

  List<AiProviderConfig> get enabledProviders => state
      .where((AiProviderConfig config) => config.enabled)
      .toList(growable: false);

  Future<void> upsert(AiProviderConfig config) async {
    state = await _store.upsert(config);
    _logger.info('ai', 'Provider config saved for ${_profile.storageScope}.');
  }

  Future<void> clear() async {
    await _store.save(const <AiProviderConfig>[]);
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
  })  : _store = store ?? AiPreferencesStore(profile: profile),
        super(const AiPreferences()) {
    unawaited(load());
  }

  final AiPreferencesStore _store;

  Future<void> load() async => state = await _store.load();

  Future<void> setLanguage(AiLanguage language) async {
    if (state.language == language) return;
    state = state.copyWith(language: language);
    await _persist();
  }

  Future<void> setConsent(bool granted) async {
    if (state.consentGranted == granted) return;
    state = state.copyWith(consentGranted: granted);
    await _persist();
  }

  Future<void> selectProvider(String? providerId) async {
    if (state.selectedProviderId == providerId) return;
    state = providerId == null
        ? state.copyWith(clearSelectedProvider: true)
        : state.copyWith(selectedProviderId: providerId);
    await _persist();
  }

  Future<void> setActiveConversation(String? conversationId) async {
    if (state.activeConversationId == conversationId) return;
    state = conversationId == null
        ? state.copyWith(clearActiveConversation: true)
        : state.copyWith(activeConversationId: conversationId);
    await _persist();
  }

  Future<void> _persist() => _store.save(state);
}

/// Bounded persisted conversation list for one profile.
class AiConversationLibraryController
    extends StateNotifier<List<AiConversation>> {
  AiConversationLibraryController({
    required AuraProfile profile,
    AiConversationStore? store,
  })  : _store = store ?? AiConversationStore(profile: profile),
        super(const <AiConversation>[]) {
    unawaited(load());
  }

  final AiConversationStore _store;

  Future<void> load() async => state = await _store.load();

  void discardForLock() => state = const <AiConversation>[];

  String create() {
    final DateTime now = DateTime.now();
    final String id =
        '${now.microsecondsSinceEpoch}-${Random.secure().nextInt(65536).toRadixString(16)}';
    final AiConversation conversation = AiConversation(
      id: id,
      createdAt: now,
      updatedAt: now,
    );
    state = <AiConversation>[conversation, ...state];
    _persist();
    return id;
  }

  bool contains(String id) => state.any((AiConversation item) => item.id == id);

  Future<void> rename(String id, String title) async {
    final String clean = title.trim();
    if (clean.isEmpty) return;
    state = state
        .map((AiConversation item) => item.id == id
            ? item.copyWith(title: clean, updatedAt: DateTime.now())
            : item)
        .toList();
    _sort();
    await _store.save(state);
  }

  Future<void> delete(String id) async {
    state = state
        .where((AiConversation item) => item.id != id)
        .toList(growable: false);
    await _store.save(state);
  }

  void appendMessage(String conversationId, AiMessage message) {
    bool changed = false;
    state = state.map((AiConversation item) {
      if (item.id != conversationId) return item;
      changed = true;
      return item.append(message);
    }).toList(growable: false);
    if (!changed) return;
    _sort();
    _persist();
  }

  Future<void> clear(String conversationId) async {
    state = state
        .map((AiConversation item) =>
            item.id == conversationId ? item.clear() : item)
        .toList(growable: false);
    await _store.save(state);
  }

  void _sort() {
    final List<AiConversation> sorted = List<AiConversation>.from(state)
      ..sort((AiConversation a, AiConversation b) =>
          b.sortTime.compareTo(a.sortTime));
    state = sorted;
  }

  void _persist() => unawaited(_store.save(state));
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
    AiDiagnostics? diagnostics,
    AiContextAssembler? contextAssembler,
  })  : _configs = configs,
        _preferences = preferences,
        _conversations = conversations,
        _credentials = credentials,
        _client = client,
        _logger = logger,
        _diagnostics = diagnostics ?? const NoAiDiagnostics(),
        _contextAssembler =
            contextAssembler ?? const DefaultAiContextAssembler(),
        super(const AiChatState());

  final AuraProfile profile;
  final ProfileAccess access;
  final AiConfigController _configs;
  final AiPreferencesController _preferences;
  final AiConversationLibraryController _conversations;
  final AiCredentialController _credentials;
  final AiClient _client;
  final AuraLogger _logger;
  final AiDiagnostics _diagnostics;
  final AiContextAssembler _contextAssembler;

  AiCancelToken? _cancelToken;
  String? _lastPrompt;

  Future<void> send(String rawText) async {
    final String text = rawText.trim();
    if (text.isEmpty || state.isBusy) return;

    if (!access.canRead(profile)) {
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

    String conversationId = _preferences.state.activeConversationId ?? '';
    if (!_conversations.contains(conversationId)) {
      conversationId = _conversations.create();
      await _preferences.setActiveConversation(conversationId);
    }
    _conversations.appendMessage(
      conversationId,
      AiMessage(
        role: AiMessageRole.user,
        content: text,
        timestamp: DateTime.now(),
      ),
    );
    _lastPrompt = text;
    await _runCompletion(conversationId: conversationId);
  }

  /// Retries the last user prompt without duplicating it in the transcript.
  Future<void> retry() async {
    final String? conversationId = _preferences.state.activeConversationId;
    if (_lastPrompt == null || conversationId == null || state.isBusy) return;
    await _runCompletion(conversationId: conversationId);
  }

  void cancel() => _cancelToken?.cancel();

  void clearError() {
    if (state.hasError) {
      state = state.copyWith(clearError: true);
    }
  }

  void discardForLock() {
    cancel();
    _lastPrompt = null;
    state = const AiChatState();
  }

  Future<void> _runCompletion({required String conversationId}) async {
    if (state.isBusy) return;

    AiProviderConfig? config;
    try {
      config = _selectedConfig();
    } on AiException catch (error) {
      state = AiChatState(
        failureKind: error.kind,
        errorMessage: error.message,
      );
      return;
    }
    if (config == null) {
      state = const AiChatState(
        failureKind: AiFailureKind.needsConfiguration,
        errorMessage: 'Select an enabled, valid provider first.',
      );
      return;
    }

    final String? apiKey = await _credentials.resolveKey(providerId: config.id);
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
    final AiAssembledContext assembled = _contextAssembler.assemble(
      AiContextRequest(
        profile: profile,
        historyProfile: profile,
        history: conversation.list(),
        language: language,
      ),
    );
    if (assembled.isEmpty) {
      state = const AiChatState(
        failureKind: AiFailureKind.payloadTooLarge,
        errorMessage:
            'The current message is unavailable or too large for the context budget.',
      );
      return;
    }

    final AiCancelToken token = AiCancelToken();
    _cancelToken = token;
    final StringBuffer buffer = StringBuffer();
    final Stopwatch elapsed = Stopwatch()..start();
    int chunks = 0;
    state = const AiChatState(isBusy: true, streamingText: '');

    try {
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
        if (token.isCancelled) break;
        buffer.write(delta);
        chunks++;
        state = AiChatState(isBusy: true, streamingText: buffer.toString());
      }

      final String response = buffer.toString().trim();
      if (token.isCancelled) {
        // The transport may close normally after abort. Partial text must be
        // labelled interrupted, never presented as a complete answer.
        if (response.isNotEmpty) {
          _appendAssistant(conversationId, response, interrupted: true);
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
      _appendAssistant(conversationId, response, interrupted: false);
      _recordPersist(config, AiDiagnosticOutcome.succeeded, chunks, elapsed);
      _lastPrompt = null;
      state = const AiChatState();
    } on AiException catch (error) {
      final bool wasCancelled =
          token.isCancelled || error.kind == AiFailureKind.cancelled;
      final String partial = buffer.toString().trim();
      if (partial.isNotEmpty) {
        _appendAssistant(conversationId, partial, interrupted: true);
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
      final String partial = buffer.toString().trim();
      if (partial.isNotEmpty) {
        _appendAssistant(conversationId, partial, interrupted: true);
      }
      _recordPersist(config, AiDiagnosticOutcome.failed, chunks, elapsed);
      state = const AiChatState(
        failureKind: AiFailureKind.unknown,
        errorMessage: 'The assistant could not complete the response.',
      );
      _logger.warning('ai', 'Completion failed with an unexpected error');
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
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
    required bool interrupted,
  }) {
    _conversations.appendMessage(
      conversationId,
      AiMessage(
        role: AiMessageRole.assistant,
        content: content,
        timestamp: DateTime.now(),
        isInterrupted: interrupted,
      ),
    );
  }

  AiProviderConfig? _selectedConfig() {
    final String? selectedId = _preferences.state.selectedProviderId;
    final AiProviderConfig? selected = selectedId == null
        ? null
        : _configs.state.firstWhere(
            (AiProviderConfig item) => item.id == selectedId,
            orElse: () => const AiProviderConfig(
              id: '',
              label: '',
              kind: AiProviderKind.openAiCompatible,
              baseUrl: '',
              model: '',
            ),
          );
    final AiProviderConfig? effective = selected ??
        (_configs.enabledProviders.isEmpty
            ? null
            : _configs.enabledProviders.first);
    if (effective == null || !effective.enabled) return null;
    if (effective.validate() != null) {
      throw const AiException(
        AiFailureKind.configuration,
        'The selected provider configuration is incomplete.',
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
  });

  final AiConnectionStatus status;
  final String? message;
  final DateTime? testedAt;

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
    bool clearMessage = false,
  }) {
    return AiConnectionState(
      status: status ?? this.status,
      message: clearMessage ? null : message ?? this.message,
      testedAt: testedAt ?? this.testedAt,
      verifiedProviderId: verifiedProviderId ?? this.verifiedProviderId,
      verifiedSignature: verifiedSignature ?? this.verifiedSignature,
    );
  }
}

/// Performs real provider connection tests. Never reports success from a saved
/// key alone.
class AiConnectionController extends StateNotifier<AiConnectionState> {
  AiConnectionController({
    required AiConfigController configs,
    required AiCredentialController credentials,
    required AiClient client,
    required AuraLogger logger,
  })  : _configs = configs,
        _credentials = credentials,
        _client = client,
        _logger = logger,
        super(const AiConnectionState());

  final AiConfigController _configs;
  final AiCredentialController _credentials;
  final AiClient _client;
  final AuraLogger _logger;
  AiCancelToken? _cancelToken;

  Future<void> test({required String providerId}) async {
    if (state.status == AiConnectionStatus.testing) return;
    final AiProviderConfig config = _configs.state.firstWhere(
      (AiProviderConfig item) => item.id == providerId,
      orElse: () => const AiProviderConfig(
        id: '',
        label: '',
        kind: AiProviderKind.openAiCompatible,
        baseUrl: '',
        model: '',
      ),
    );
    if (config.id.isEmpty || config.validate() != null) {
      state = const AiConnectionState(
        status: AiConnectionStatus.error,
        message: 'Complete the provider configuration before testing.',
      );
      return;
    }

    final String? apiKey =
        await _credentials.resolveKey(providerId: providerId);
    if (!config.isLocal && (apiKey == null || apiKey.isEmpty)) {
      state = const AiConnectionState(
        status: AiConnectionStatus.error,
        message: 'Add an API key before testing this provider.',
      );
      return;
    }

    final AiCancelToken token = AiCancelToken();
    _cancelToken = token;
    state = const AiConnectionState(status: AiConnectionStatus.testing);
    try {
      await _client.testConnection(
        config: config,
        context: AiRequestContext(apiKey: apiKey, cancelToken: token),
      );
      state = AiConnectionState(
        status: AiConnectionStatus.connected,
        message: 'Metadata access verified with /models.',
        testedAt: DateTime.now(),
        verifiedProviderId: config.id,
        verifiedSignature: AiConnectionState._signature(config),
      );
      _logger.info('ai', 'Provider metadata test succeeded.');
    } on AiException catch (error) {
      state = AiConnectionState(
        status: AiConnectionStatus.error,
        message: error.message,
        testedAt: DateTime.now(),
      );
      _logger.warning(
          'ai', 'Provider connection test failed (${error.kind.name})');
    } catch (_) {
      state = const AiConnectionState(
        status: AiConnectionStatus.error,
        message: 'The connection test could not be completed.',
        testedAt: null,
      );
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
    }
  }

  void cancel() => _cancelToken?.cancel();

  void markDisconnected() {
    state = const AiConnectionState(status: AiConnectionStatus.disconnected);
  }

  /// Called when configuration, selection or credentials change. A previous
  /// `/models` result must not be presented as valid for the new setup.
  void invalidate() {
    if (state.status == AiConnectionStatus.connected ||
        state.status == AiConnectionStatus.needsRefresh) {
      state = AiConnectionState(
        status: AiConnectionStatus.needsRefresh,
        message: 'Provider details changed. Test the connection again.',
        testedAt: state.testedAt,
      );
    }
  }

  void discardForLock() {
    cancel();
    state = const AiConnectionState();
  }

  @override
  void dispose() {
    cancel();
    super.dispose();
  }
}

enum AiCredentialPresence { unknown, present, missing }

class AiCredentialState {
  const AiCredentialState({this.presence = AiCredentialPresence.unknown});

  final AiCredentialPresence presence;

  AiCredentialState copyWith({AiCredentialPresence? presence}) =>
      AiCredentialState(presence: presence ?? this.presence);
}

/// Tracks only whether a key exists. The raw key never enters Riverpod state.
class AiCredentialController extends StateNotifier<AiCredentialState> {
  AiCredentialController({
    required this.profile,
    required AiCredentialStore store,
  })  : _store = store,
        super(const AiCredentialState()) {
    refresh();
  }

  final AuraProfile profile;
  final AiCredentialStore _store;

  Future<void> refresh({String? providerId}) async {
    if (providerId == null) {
      state = const AiCredentialState();
      return;
    }
    final bool hasKey = await _store.has(
      profileScope: profile.storageScope,
      providerId: providerId,
    );
    state = AiCredentialState(
      presence:
          hasKey ? AiCredentialPresence.present : AiCredentialPresence.missing,
    );
  }

  Future<void> save({
    required String providerId,
    required String apiKey,
  }) async {
    await _store.save(
      profileScope: profile.storageScope,
      providerId: providerId,
      apiKey: apiKey,
    );
    state = const AiCredentialState(presence: AiCredentialPresence.present);
  }

  Future<void> delete({required String providerId}) async {
    await _store.delete(
      profileScope: profile.storageScope,
      providerId: providerId,
    );
    state = const AiCredentialState(presence: AiCredentialPresence.missing);
  }

  /// Transient request-time resolution; never store this in state or logs.
  Future<String?> resolveKey({required String providerId}) => _store.readSecret(
        profileScope: profile.storageScope,
        providerId: providerId,
      );

  void discardForLock() => state = const AiCredentialState();
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

final Provider<AiCredentialStore> aiCredentialStoreProvider =
    Provider<AiCredentialStore>((Ref ref) => AiCredentialStore());

final Provider<AiDiagnostics> aiDiagnosticsProvider = Provider<AiDiagnostics>(
  (Ref ref) => AuraAiDiagnostics(ref.read(auraLoggerProvider.notifier)),
);

final Provider<AiClient> aiClientProvider = Provider<AiClient>((Ref ref) {
  return OpenAiCompatibleAiClient(
    transport: const DartIoAiHttpTransport(),
    diagnostics: ref.read(aiDiagnosticsProvider),
  );
});

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

final ProviderFamily<AiConversationStore, AuraProfile>
    aiConversationStoreForProvider =
    ProviderFamily<AiConversationStore, AuraProfile>(
  (Ref ref, AuraProfile profile) => AiConversationStore(profile: profile),
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
  return AiPreferencesController(
    profile: profile,
    store: ref.read(aiPreferencesStoreForProvider(profile)),
  );
});

final StateNotifierProviderFamily<AiConversationLibraryController,
        List<AiConversation>, AuraProfile> aiConversationsForProvider =
    StateNotifierProvider.family<AiConversationLibraryController,
        List<AiConversation>, AuraProfile>((Ref ref, AuraProfile profile) {
  _guardProfile(ref, profile);
  final AiConversationLibraryController controller =
      AiConversationLibraryController(
    profile: profile,
    store: ref.read(aiConversationStoreForProvider(profile)),
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
      configs: ref.read(aiConfigsForProvider(profile).notifier),
      preferences: ref.read(aiPreferencesForProvider(profile).notifier),
      conversations: ref.read(aiConversationsForProvider(profile).notifier),
      credentials: ref.read(aiCredentialsForProvider(profile).notifier),
      client: ref.read(aiClientProvider),
      logger: ref.read(auraLoggerProvider.notifier),
      diagnostics: ref.read(aiDiagnosticsProvider),
      contextAssembler: ref.read(aiContextAssemblerProvider),
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
  );
  _watchLock(ref, profile, controller.discardForLock);
  return controller;
});

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

final Provider<AiReadiness> aiReadinessProvider =
    Provider<AiReadiness>((Ref ref) {
  final List<AiProviderConfig> configs = ref.watch(activeAiConfigsProvider);
  final AiPreferences preferences = ref.watch(activeAiPreferencesProvider);
  final AiCredentialState credentials =
      ref.watch(activeAiCredentialStateProvider);
  final AiConnectionState connection =
      ref.watch(activeAiConnectionStateProvider);

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
