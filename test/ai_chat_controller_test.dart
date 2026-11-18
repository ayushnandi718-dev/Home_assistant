import 'dart:async';
import 'dart:io';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/data/ai_preferences_store.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
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
  Future<void> write({required String target, required String secret}) async =>
      secrets[target] = secret;

  @override
  Future<String?> read({required String target}) async => secrets[target];

  @override
  Future<bool> delete({required String target}) async =>
      secrets.remove(target) != null;
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

  void failNext() => _failNext = true;

  void emit(String value) => _active!.add(value);
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

Future<void> _waitUntil(
  bool Function() ready, {
  String message = 'Expected asynchronous AI work to finish.',
}) async {
  for (int attempt = 0; attempt < 100; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
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

  Future<void> setUp({required bool consent, bool storeKey = true}) async {
    directory = Directory.systemTemp.createTempSync('aura_ai_chat_');
    configs = AiConfigController(
      profile: AuraProfile.family,
      store: AiConfigStore(directory: directory, profile: AuraProfile.family),
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
    );
    await conversations.load();

    credentials = AiCredentialController(
      profile: AuraProfile.family,
      store: AiCredentialStore(vault: MemoryVault()),
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
      configs: configs,
      preferences: preferences,
      conversations: conversations,
      credentials: credentials,
      client: client,
      logger: AuraLogger(),
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
      } on PathAccessException {
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
}
