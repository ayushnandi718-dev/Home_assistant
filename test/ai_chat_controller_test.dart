import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/data/ai_preferences_store.dart';
import 'package:aura_hub/features/ai/data/default_ai_context_assembler.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_context.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryVault implements CredentialVault {
  final Map<String, String> secrets = <String, String>{};

  @override
  Future<void> write(
          {required String target,
          required String secret,
          bool Function()? isCommitAllowed}) async =>
      secrets[target] = secret;

  @override
  Future<String?> read({required String target}) async => secrets[target];

  @override
  Future<bool> delete(
          {required String target, bool Function()? isCommitAllowed}) async =>
      secrets.remove(target) != null;
}

/// Test-only vault that can hold credential reads open with a [Completer].
///
/// Lets a test start two operations before either credential resolution
/// finishes, without relying on sleeps or wall-clock timing. The underlying
/// store is still an in-memory fake; no real secret store is contacted.
class GatedVault implements CredentialVault {
  GatedVault(this._inner);

  final CredentialVault _inner;
  final Queue<Completer<void>> _gates = Queue<Completer<void>>();
  int readCount = 0;

  /// When set, the next gated read throws instead of returning a key.
  Object? throwOnRead;

  Completer<void> gateNextRead() {
    final Completer<void> gate = Completer<void>();
    _gates.add(gate);
    return gate;
  }

  @override
  Future<void> write(
          {required String target,
          required String secret,
          bool Function()? isCommitAllowed}) =>
      _inner.write(target: target, secret: secret);

  @override
  Future<bool> delete(
          {required String target, bool Function()? isCommitAllowed}) =>
      _inner.delete(target: target);

  @override
  Future<String?> read({required String target}) async {
    readCount++;
    if (_gates.isNotEmpty) await _gates.removeFirst().future;
    if (throwOnRead != null) throw throwOnRead!;
    return _inner.read(target: target);
  }
}

class FakeAiClient implements AiClient {
  StreamController<String>? _active;
  int callCount = 0;
  bool _failNext = false;
  AiProviderConfig? lastConfig;
  List<AiMessage>? lastMessages;
  AiLanguage? lastLanguage;
  AiRequestContext? lastContext;

  bool get hasActiveStream => _active != null && !_active!.isClosed;

  /// Most recent stream controller, for controlled late-delta injection.
  StreamController<String> get activeStream => _active!;

  void failNext() => _failNext = true;

  void emit(String value) => _active!.add(value);
  void emitError(Object error) => _active!.addError(error);
  void complete() => _active!.close();

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.english,
    AiRequestContext? context,
  }) {
    callCount++;
    lastConfig = config;
    lastMessages = List<AiMessage>.from(messages);
    lastLanguage = language;
    lastContext = context;
    if (_failNext) {
      _failNext = false;
      final StreamController<String> failing = StreamController<String>();
      failing.addError(
        const AiException(
          AiFailureKind.rateLimited,
          'Rate limited by provider.',
        ),
      );
      unawaited(failing.close());
      return failing.stream;
    }
    _active = StreamController<String>();
    return _active!.stream;
  }

  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {}
}

class RecordingContextAssembler implements AiContextAssembler {
  static const String marker = 'PHASE1-CONTEXT-OK';

  AiContextRequest? lastRequest;

  @override
  AiAssembledContext assemble(AiContextRequest request) {
    lastRequest = request;
    final AiAssembledContext safe =
        const DefaultAiContextAssembler().assemble(request);
    return AiAssembledContext(
      messages: safe.messages,
      systemInstructions: <String>[...safe.systemInstructions, marker],
      includedSources: safe.includedSources,
      unavailableSources: safe.unavailableSources,
      estimatedTokens: safe.estimatedTokens,
      budgetTokens: safe.budgetTokens,
    );
  }
}

Future<void> _waitUntil(
  bool Function() ready, {
  String message = 'Expected asynchronous AI work to finish.',
}) async {
  // The full suite runs many isolates concurrently, so credential resolution
  // and local preference writes can take longer than a few milliseconds on a
  // busy machine. Poll for readiness instead of assuming a fixed deadline.
  for (int attempt = 0; attempt < 500; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(message);
}

class _Harness {
  late Directory directory;
  late AiConfigController configs;
  late AiPreferencesController preferences;
  late AiConversationLibraryController conversations;
  late AiCredentialController credentials;
  late FakeAiClient client;
  late AiChatController chat;

  Future<void> setUp({
    required bool consent,
    bool storeKey = true,
    AiContextAssembler? contextAssembler,
    CredentialVault? vault,
  }) async {
    directory = Directory.systemTemp.createTempSync('aura_ai_chat_');
    configs = AiConfigController(
      profile: AuraProfile.family,
      store: AiConfigStore(directory: directory, profile: AuraProfile.family),
      accessReader: () => ProfileAccess(ProfileSession.initial),
    );
    await configs.load();
    await configs.upsert(
      const AiProviderConfig(
        id: 'groq',
        label: 'Groq test',
        kind: AiProviderKind.openAiCompatible,
        baseUrl: 'https://api.groq.com/openai/v1',
        model: 'user-model',
        enabled: true,
      ),
    );

    preferences = AiPreferencesController(
      profile: AuraProfile.family,
      store: AiPreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      ),
      accessReader: () => ProfileAccess(ProfileSession.initial),
    );
    await preferences.load();
    await preferences.setLanguage(AiLanguage.bengali);
    await preferences.selectProvider('groq');
    if (consent) await preferences.setConsent(true);

    conversations = AiConversationLibraryController(
      profile: AuraProfile.family,
      store: AiConversationStore(
        directory: directory,
        profile: AuraProfile.family,
      ),
      accessReader: () => ProfileAccess(ProfileSession.initial),
    );
    await conversations.load();

    credentials = AiCredentialController(
      profile: AuraProfile.family,
      store: AiCredentialStore(vault: vault ?? MemoryVault()),
      accessReader: () => ProfileAccess(ProfileSession.initial),
    );
    if (storeKey) {
      await credentials.save(providerId: 'groq', apiKey: 'FAKE-KEY');
    }

    client = FakeAiClient();
    chat = AiChatController(
      profile: AuraProfile.family,
      access: ProfileAccess(ProfileSession(
        profile: AuraProfile.family,
        startedAt: DateTime(1970),
      )),
      accessReader: () => ProfileAccess(ProfileSession.initial),
      configs: configs,
      preferences: preferences,
      conversations: conversations,
      credentials: credentials,
      client: client,
      logger: AuraLogger(),
      contextAssembler: contextAssembler,
    );
  }

  Future<void> tearDown() async {
    // Conversation persistence is intentionally fire-and-forget in the UI.
    // Give pending writes time to finish before removing the temp directory.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    chat.dispose();
    credentials.dispose();
    conversations.dispose();
    preferences.dispose();
    configs.dispose();
    for (int attempt = 0; attempt < 10; attempt++) {
      if (!directory.existsSync()) return;
      try {
        directory.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }
}

void main() {
  group('AiChatController', () {
    late _Harness harness;

    setUp(() async {
      harness = _Harness();
      await harness.setUp(consent: true);
    });

    tearDown(() => harness.tearDown());

    test('sends the transcript once and persists the completed response',
        () async {
      final Future<void> sending = harness.chat.send('hello assistant');

      await _waitUntil(() => harness.client.hasActiveStream);
      expect(harness.chat.state.isBusy, isTrue);
      expect(harness.conversations.state, hasLength(1));
      expect(
        harness.conversations.state.single.list().single.content,
        'hello assistant',
      );

      harness.client.emit('Hello ');
      await Future<void>.delayed(Duration.zero);
      expect(harness.chat.state.streamingText, 'Hello ');
      harness.client.emit('world');
      await Future<void>.delayed(Duration.zero);
      expect(harness.chat.state.streamingText, 'Hello world');
      harness.client.complete();
      await sending;

      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(messages, hasLength(2));
      expect(messages.last.role, AiMessageRole.assistant);
      expect(messages.last.content, 'Hello world');
      expect(messages.last.isInterrupted, isFalse);
      expect(harness.chat.state.isBusy, isFalse);
      expect(harness.chat.state.streamingText, isNull);
      expect(harness.client.callCount, 1);
      expect(harness.client.lastLanguage, AiLanguage.bengali);
      expect(harness.client.lastMessages!.single.content, 'hello assistant');
      expect(harness.client.lastContext!.apiKey, 'FAKE-KEY');
    });

    test('blocks abusive slang before persisting or calling the provider',
        () async {
      await harness.chat.send('you bhenchod idiot');

      expect(harness.chat.state.hasError, isTrue);
      expect(harness.chat.state.failureKind, AiFailureKind.badRequest);
      expect(harness.chat.state.errorMessage, contains('respectful'));
      expect(harness.client.callCount, 0);
      expect(harness.conversations.state, isEmpty);
    });

    test('persists partial output as interrupted when generation is cancelled',
        () async {
      final Future<void> sending = harness.chat.send('start');
      await _waitUntil(() => harness.client.hasActiveStream);

      harness.client.emit('partial answer');
      await Future<void>.delayed(Duration.zero);
      expect(harness.chat.state.streamingText, 'partial answer');
      harness.chat.cancel();
      harness.client.complete();
      await sending;

      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(messages.last.content, 'partial answer');
      expect(messages.last.isInterrupted, isTrue);
      expect(harness.chat.state.hasError, isFalse);
      expect(harness.chat.state.isBusy, isFalse);
    });

    test('retry reuses the last prompt without duplicating the user message',
        () async {
      harness.client.failNext();
      await harness.chat.send('retry me');

      expect(harness.chat.state.failureKind, AiFailureKind.rateLimited);
      expect(
        harness.conversations.state.single
            .list()
            .where((AiMessage message) => message.role == AiMessageRole.user)
            .length,
        1,
      );

      final Future<void> retrying = harness.chat.retry();
      await _waitUntil(
        () => harness.client.callCount == 2 && harness.client.hasActiveStream,
      );
      harness.client.emit('recovered');
      await Future<void>.delayed(Duration.zero);
      harness.client.complete();
      await retrying;

      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(
        messages
            .where((AiMessage message) => message.role == AiMessageRole.user),
        hasLength(1),
      );
      expect(messages.last.content, 'recovered');
      expect(harness.chat.state.hasError, isFalse);
    });

    test('missing credentials block sending before any provider call',
        () async {
      final _Harness missing = _Harness();
      await missing.setUp(consent: true, storeKey: false);
      addTearDown(missing.tearDown);

      await missing.chat.send('needs a key');
      expect(
        missing.chat.state.failureKind,
        AiFailureKind.missingCredentials,
      );
      expect(missing.client.callCount, 0);
      // The typed prompt is kept locally so the user does not lose it, but it
      // never reaches a provider without credentials.
      expect(missing.conversations.state, hasLength(1));
      expect(
        missing.conversations.state.single.list().single.role,
        AiMessageRole.user,
      );
    });
  });

  group('Consent enforcement', () {
    late _Harness harness;

    setUp(() async {
      harness = _Harness();
      await harness.setUp(consent: false);
    });

    tearDown(() => harness.tearDown());

    test('no message leaves the device before explicit consent', () async {
      await harness.chat.send('do not transmit');

      expect(
        harness.chat.state.failureKind,
        AiFailureKind.consentRequired,
      );
      expect(harness.client.callCount, 0);
      expect(harness.conversations.state, isEmpty);
    });

    test('revoking consent blocks later requests', () async {
      await harness.preferences.setConsent(true);
      final Future<void> sending = harness.chat.send('first allowed');
      await _waitUntil(() => harness.client.hasActiveStream);
      harness.client.complete();
      await sending;

      await harness.preferences.setConsent(false);
      await harness.chat.send('second blocked');

      expect(harness.client.callCount, 1);
      expect(
        harness.chat.state.failureKind,
        AiFailureKind.consentRequired,
      );
    });
  });

  group('Context assembly wiring', () {
    late _Harness harness;
    late RecordingContextAssembler assembler;

    setUp(() async {
      harness = _Harness();
      assembler = RecordingContextAssembler();
      await harness.setUp(consent: true, contextAssembler: assembler);
    });

    tearDown(() => harness.tearDown());

    test('assembled profile-safe context reaches the streaming pipeline',
        () async {
      final Future<void> sending = harness.chat.send('hello with context');

      await _waitUntil(() => harness.client.hasActiveStream);

      expect(assembler.lastRequest, isNotNull);
      expect(assembler.lastRequest!.profile, AuraProfile.family);
      expect(assembler.lastRequest!.historyProfile, AuraProfile.family);
      expect(harness.client.lastMessages!.last.content, 'hello with context');
      expect(harness.client.lastContext!.assembledContext, isNotNull);
      expect(
        harness.client.lastContext!.assembledContext!.systemInstructions,
        contains(RecordingContextAssembler.marker),
      );

      harness.client.emit('assembled reply');
      harness.client.complete();
      await sending;

      expect(
        harness.conversations.state.single.list().last.content,
        'assembled reply',
      );
    });
  });

  group('Chat generation concurrency', () {
    test(
        'overlapping sends before credential resolution yield exactly one '
        'accepted generation', () async {
      final _Harness harness = _Harness();
      final GatedVault gated = GatedVault(MemoryVault());
      final Completer<void> firstRead = gated.gateNextRead();
      await harness.setUp(consent: true, vault: gated);
      addTearDown(harness.tearDown);

      final Future<void> first = harness.chat.send('first prompt');
      await _waitUntil(() => gated.readCount == 1);
      expect(harness.chat.state.isBusy, isTrue);

      // The guard is held synchronously, so this cannot start a second
      // generation even though the first has not reached its stream yet.
      final Future<void> second = harness.chat.send('second prompt');
      await Future<void>.delayed(Duration.zero);
      expect(gated.readCount, 1);
      expect(harness.client.callCount, 0);

      firstRead.complete();
      await _waitUntil(() => harness.client.hasActiveStream);
      expect(harness.client.callCount, 1);

      harness.client.emit('only answer');
      await Future<void>.delayed(Duration.zero);
      harness.client.complete();
      await Future.wait<void>(<Future<void>>[first, second]);

      expect(gated.readCount, 1);
      expect(harness.client.callCount, 1);
      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(
        messages.where((AiMessage m) => m.role == AiMessageRole.user),
        hasLength(1),
      );
      expect(messages.first.content, 'first prompt');
      expect(
        messages.where((AiMessage m) => m.role == AiMessageRole.assistant),
        hasLength(1),
      );
      expect(messages.last.content, 'only answer');
      expect(harness.chat.state.isBusy, isFalse);
    });

    test('a second send while a stream is active cannot duplicate messages',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp(consent: true);
      addTearDown(harness.tearDown);

      final Future<void> first = harness.chat.send('streaming prompt');
      await _waitUntil(() => harness.client.hasActiveStream);
      expect(harness.client.callCount, 1);

      final Future<void> second = harness.chat.send('overlap prompt');
      await Future<void>.delayed(Duration.zero);
      expect(harness.client.callCount, 1);

      harness.client.emit('single reply');
      await Future<void>.delayed(Duration.zero);
      harness.client.complete();
      await Future.wait<void>(<Future<void>>[first, second]);

      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(
        messages.where((AiMessage m) => m.role == AiMessageRole.user),
        hasLength(1),
      );
      expect(
        messages.where((AiMessage m) => m.role == AiMessageRole.assistant),
        hasLength(1),
      );
      expect(messages.last.content, 'single reply');
      expect(harness.chat.state.isBusy, isFalse);
    });

    test(
        'cancelling the active generation owns the request token and drops '
        'late deltas', () async {
      final _Harness harness = _Harness();
      await harness.setUp(consent: true);
      addTearDown(harness.tearDown);

      final Future<void> sending = harness.chat.send('cancel me');
      await _waitUntil(() => harness.client.hasActiveStream);
      final AiCancelToken? owned = harness.client.lastContext?.cancelToken;
      expect(owned, isNotNull);
      expect(owned!.isCancelled, isFalse);

      harness.chat.cancel();
      expect(owned.isCancelled, isTrue);

      // A late delta arrives after cancellation: ownership checks must stop it
      // from being published as streaming text or a completed answer.
      harness.client.emit('late text');
      await Future<void>.delayed(Duration.zero);
      expect(harness.chat.state.streamingText ?? '', isEmpty);

      harness.client.complete();
      await sending;

      expect(harness.chat.state.isBusy, isFalse);
      expect(harness.chat.state.hasError, isFalse);
      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(messages.map((AiMessage m) => m.content),
          isNot(contains('late text')));
    });

    test('cancelling before the first stream clears the busy state', () async {
      final _Harness harness = _Harness();
      final GatedVault gated = GatedVault(MemoryVault());
      final Completer<void> credentialRead = gated.gateNextRead();
      await harness.setUp(consent: true, vault: gated);
      addTearDown(harness.tearDown);

      final Future<void> sending =
          harness.chat.send('cancel before credentials resolve');
      await _waitUntil(() => gated.readCount == 1);
      expect(harness.chat.state.isBusy, isTrue);

      harness.chat.cancel();
      credentialRead.complete();
      await sending;

      expect(harness.client.callCount, 0);
      expect(harness.chat.state.isBusy, isFalse);
      expect(harness.chat.state.streamingText, isNull);
      expect(harness.chat.state.hasError, isFalse);
      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(
        messages.where((AiMessage m) => m.role == AiMessageRole.assistant),
        isEmpty,
      );
    });

    test('a stale generation cannot clear a newer generation or publish text',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp(consent: true);
      addTearDown(harness.tearDown);

      final Future<void> first = harness.chat.send('first generation');
      await _waitUntil(() => harness.client.hasActiveStream);
      final StreamController<String> firstStream = harness.client.activeStream;

      // Lock cleanup invalidates the first generation and releases its guard.
      harness.chat.discardForLock();
      expect(harness.chat.state.isBusy, isFalse);

      final Future<void> second = harness.chat.send('second generation');
      await _waitUntil(
        () => harness.client.callCount == 2 && harness.client.hasActiveStream,
      );
      final StreamController<String> secondStream = harness.client.activeStream;
      expect(secondStream, isNot(same(firstStream)));

      // The old stream completes after the new generation owns the controller.
      firstStream.add('stale answer');
      await firstStream.close();
      await Future<void>.delayed(Duration.zero);
      expect(harness.chat.state.streamingText, isEmpty);
      expect(harness.chat.state.isBusy, isTrue);

      secondStream.add('fresh answer');
      await secondStream.close();
      await Future.wait<void>(<Future<void>>[first, second]);

      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(
        messages.where((AiMessage m) => m.role == AiMessageRole.user).length,
        2,
      );
      expect(
        messages
            .where((AiMessage m) => m.role == AiMessageRole.assistant)
            .map((AiMessage m) => m.content),
        <String>['fresh answer'],
      );
      expect(messages.map((AiMessage m) => m.content),
          isNot(contains('stale answer')));
      expect(harness.chat.state.isBusy, isFalse);
    });

    test(
        'credential-resolution failure releases the guard and a later send '
        'succeeds', () async {
      final _Harness harness = _Harness();
      final GatedVault gated = GatedVault(MemoryVault());
      final Completer<void> firstRead = gated.gateNextRead();
      gated.throwOnRead = StateError('vault unavailable');
      await harness.setUp(consent: true, vault: gated);
      addTearDown(harness.tearDown);

      final Future<void> failing = harness.chat.send('needs a key');
      await _waitUntil(() => gated.readCount == 1);
      firstRead.complete();
      await failing;

      expect(harness.chat.state.failureKind, AiFailureKind.credentialStorage);
      expect(
        harness.chat.state.errorMessage,
        isNot(contains('vault unavailable')),
      );
      expect(harness.client.callCount, 0);
      expect(harness.chat.state.isBusy, isFalse);

      // Guard cleanup after the failure path allows a normal retry.
      gated.throwOnRead = null;
      final Future<void> retrying = harness.chat.send('recovered');
      await _waitUntil(
        () => harness.client.callCount == 1 && harness.client.hasActiveStream,
      );
      harness.client.emit('ok');
      harness.client.complete();
      await retrying;

      expect(gated.readCount, 2);
      expect(harness.chat.state.isBusy, isFalse);
      expect(harness.chat.state.hasError, isFalse);
      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(
        messages
            .where((AiMessage m) => m.role == AiMessageRole.assistant)
            .last
            .content,
        'ok',
      );
    });

    test(
        'an unexpected stream error terminates the generation and releases '
        'the guard', () async {
      final _Harness harness = _Harness();
      await harness.setUp(consent: true);
      addTearDown(harness.tearDown);

      final Future<void> failing = harness.chat.send('unexpected');
      await _waitUntil(() => harness.client.hasActiveStream);
      harness.client.emitError(StateError('unexpected stream failure'));
      await failing;

      expect(harness.chat.state.failureKind, AiFailureKind.unknown);
      expect(harness.chat.state.isBusy, isFalse);
      expect(harness.client.callCount, 1);

      // A subsequent valid send proves the in-flight guard was cleared.
      final Future<void> next = harness.chat.send('after failure');
      await _waitUntil(
        () => harness.client.callCount == 2 && harness.client.hasActiveStream,
      );
      harness.client.emit('fine now');
      harness.client.complete();
      await next;
      expect(harness.chat.state.isBusy, isFalse);
      expect(harness.chat.state.hasError, isFalse);
    });

    test(
        'retry after a provider failure creates one generation without '
        'duplicating the prompt', () async {
      final _Harness harness = _Harness();
      await harness.setUp(consent: true);
      addTearDown(harness.tearDown);

      harness.client.failNext();
      await harness.chat.send('retry prompt');
      expect(harness.chat.state.failureKind, AiFailureKind.rateLimited);
      expect(harness.client.callCount, 1);
      expect(harness.chat.state.isBusy, isFalse);

      final Future<void> retrying = harness.chat.retry();
      await _waitUntil(
        () => harness.client.callCount == 2 && harness.client.hasActiveStream,
      );

      // A second retry while the first retry owns the guard is ignored.
      final Future<void> ignoredRetry = harness.chat.retry();
      await Future<void>.delayed(Duration.zero);
      expect(harness.client.callCount, 2);

      harness.client.emit('recovered');
      harness.client.complete();
      await Future.wait<void>(<Future<void>>[retrying, ignoredRetry]);

      expect(harness.client.callCount, 2);
      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(
        messages.where((AiMessage m) => m.role == AiMessageRole.user),
        hasLength(1),
      );
      expect(messages.last.content, 'recovered');
      expect(harness.chat.state.isBusy, isFalse);
    });
  });
}
