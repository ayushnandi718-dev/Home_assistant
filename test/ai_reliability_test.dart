import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/ai_preferences_store.dart';
import 'package:aura_hub/features/ai/data/openai_compatible_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_diagnostics.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
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

class ScriptedTransport implements AiHttpTransport {
  final Queue<Object> _items = Queue<Object>();
  AiHttpRequest? lastRequest;
  AiCancelToken? lastToken;

  void response({
    int statusCode = 200,
    required Stream<String> body,
  }) {
    _items.add(AiHttpResponse(statusCode: statusCode, body: body));
  }

  void sse(
    String content, {
    bool done = true,
  }) {
    final String payload = 'data: ${jsonEncode(<String, dynamic>{
          'choices': <dynamic>[
            <String, dynamic>{
              'delta': <String, dynamic>{'content': content},
            },
          ],
        })}\n\n';
    response(
        body:
            Stream<String>.value('$payload${done ? 'data: [DONE]\n\n' : ''}'));
  }

  void error(Object error) => _items.add(error);

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    lastRequest = request;
    lastToken = cancelToken;
    if (_items.isEmpty) throw StateError('No scripted transport result.');
    final Object next = _items.removeFirst();
    if (next is AiHttpResponse) return next;
    throw next;
  }
}

class RecordingDiagnostics extends AiDiagnostics {
  final List<AiDiagnosticEvent> events = <AiDiagnosticEvent>[];

  @override
  void record(AiDiagnosticEvent event) => events.add(event);
}

AiProviderConfig _config({
  String id = 'groq',
  String baseUrl = 'https://api.groq.com/openai/v1',
  String model = 'user-selected-model',
}) =>
    AiProviderConfig(
      id: id,
      label: 'Groq test',
      kind: AiProviderKind.openAiCompatible,
      baseUrl: baseUrl,
      model: model,
      enabled: true,
    );

Future<void> _pump() => Future<void>.delayed(Duration.zero);

Future<void> _waitUntil(
  bool Function() ready, {
  String message = 'Expected asynchronous AI work to finish.',
}) async {
  for (int attempt = 0; attempt < 300; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  fail(message);
}

class _Harness {
  late Directory directory;
  late ScriptedTransport transport;
  late RecordingDiagnostics diagnostics;
  late AuraLogger logger;
  late AiConfigController configs;
  late AiPreferencesController preferences;
  late AiConversationLibraryController conversations;
  late AiCredentialController credentials;
  late AiChatController chat;
  late AiConnectionController connection;
  late OpenAiCompatibleAiClient client;

  Future<void> setUp({
    AuraProfile profile = AuraProfile.family,
    bool consent = true,
    bool storeKey = true,
    String apiKey = 'FAKE-KEY',
  }) async {
    directory = Directory.systemTemp.createTempSync('aura_ai_reliability_');
    transport = ScriptedTransport();
    diagnostics = RecordingDiagnostics();
    logger = AuraLogger();
    client = OpenAiCompatibleAiClient(
      transport: transport,
      diagnostics: diagnostics,
    );

    configs = AiConfigController(
      profile: profile,
      store: AiConfigStore(directory: directory, profile: profile),
      logger: logger,
    );
    await configs.load();
    await configs.upsert(_config());

    preferences = AiPreferencesController(
      profile: profile,
      store: AiPreferencesStore(directory: directory, profile: profile),
    );
    await preferences.load();
    await preferences.selectProvider('groq');
    if (consent) await preferences.setConsent(true);

    conversations = AiConversationLibraryController(
      profile: profile,
      store: AiConversationStore(directory: directory, profile: profile),
    );
    await conversations.load();

    credentials = AiCredentialController(
      profile: profile,
      store: AiCredentialStore(vault: MemoryVault()),
    );
    if (storeKey) {
      await credentials.save(providerId: 'groq', apiKey: apiKey);
    }

    chat = AiChatController(
      profile: profile,
      access: ProfileAccess(ProfileSession(
        profile: profile,
        startedAt: DateTime(1970),
        authenticated: profile == AuraProfile.ayush,
      )),
      configs: configs,
      preferences: preferences,
      conversations: conversations,
      credentials: credentials,
      client: client,
      logger: logger,
      diagnostics: diagnostics,
    );
    connection = AiConnectionController(
      configs: configs,
      credentials: credentials,
      client: client,
      logger: logger,
    );
  }

  Future<void> tearDown() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    chat.dispose();
    connection.dispose();
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
  group('HTTP status classification', () {
    test('maps documented status codes to distinct safe failures', () {
      expect(aiHttpException(400).kind, AiFailureKind.badRequest);
      expect(aiHttpException(401).kind, AiFailureKind.authentication);
      expect(aiHttpException(403).kind, AiFailureKind.permissionDenied);
      expect(aiHttpException(404).kind, AiFailureKind.notFound);
      expect(aiHttpException(413).kind, AiFailureKind.payloadTooLarge);
      expect(aiHttpException(429).kind, AiFailureKind.rateLimited);
      expect(aiHttpException(500).kind, AiFailureKind.serverError);
      expect(aiHttpException(503).kind, AiFailureKind.serverError);
      for (final int code in <int>[400, 401, 403, 404, 413, 429, 500]) {
        expect(aiHttpException(code).statusCode, code);
        expect(aiHttpException(code).message, isNot(contains('Bearer')));
      }
    });

    test('authentication and configuration failures are not retryable', () {
      expect(aiHttpException(401).kind.isRetryable, isFalse);
      expect(aiHttpException(404).kind.isRetryable, isFalse);
      expect(aiHttpException(413).kind.isRetryable, isFalse);
      expect(aiHttpException(429).kind.isRetryable, isTrue);
      expect(aiHttpException(500).kind.isRetryable, isTrue);
      expect(AiFailureKind.tlsFailure.isRetryable, isTrue);
      expect(AiFailureKind.badRequest.isRetryable, isFalse);
    });
  });

  group('Transport failure classification and redacted diagnostics', () {
    late _Harness harness;

    setUp(() async {
      harness = _Harness();
      await harness.setUp();
    });

    tearDown(() => harness.tearDown());

    Future<void> expectFailure(AiFailureKind kind) async {
      await expectLater(
        harness.client
            .streamCompletion(
              config: _config(),
              messages: const <AiMessage>[],
              context: const AiRequestContext(apiKey: 'FAKE-KEY'),
            )
            .toList(),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            kind,
          ),
        ),
      );
    }

    test('socket failure is a network failure with a typed diagnostic',
        () async {
      harness.transport.error(const SocketException('Connection refused'));
      await expectFailure(AiFailureKind.networkFailure);

      final AiDiagnosticEvent event = harness.diagnostics.events.last;
      expect(event.stage, AiRequestStage.connect);
      expect(event.failureKind, AiFailureKind.networkFailure);
      expect(event.exceptionType, 'SocketException');
      expect(event.host, 'api.groq.com');
      expect(event.method, 'POST');
      expect(event.context.values, isNot(contains(contains('FAKE-KEY'))));
      expect(event.context.containsKey('body'), isFalse);
      expect(event.context.containsKey('authorization'), isFalse);
    });

    test('DNS failure is classified separately from a refused socket',
        () async {
      harness.transport.error(
        SocketException('Failed host lookup: api.groq.com'),
      );
      await expectFailure(AiFailureKind.dnsFailure);
      expect(
        harness.diagnostics.events.last.exceptionType,
        'SocketException',
      );
    });

    test('TLS handshake failure is not reported as an unknown error', () async {
      harness.transport.error(const HandshakeException('bad certificate'));
      await expectFailure(AiFailureKind.tlsFailure);

      final AiDiagnosticEvent event = harness.diagnostics.events.last;
      expect(event.exceptionType, 'HandshakeException');
      expect(event.failureKind, AiFailureKind.tlsFailure);
    });

    test('connection timeout is distinct from a streaming timeout', () async {
      harness.transport.error(TimeoutException('connect'));
      await expectFailure(AiFailureKind.connectionTimeout);
      expect(
        harness.diagnostics.events.last.stage,
        AiRequestStage.connect,
      );
    });

    test('streaming timeout is classified during body consumption', () async {
      final StreamController<String> body = StreamController<String>();
      harness.transport.response(body: body.stream);
      final Future<List<String>> reading = harness.client
          .streamCompletion(
            config: _config(),
            messages: const <AiMessage>[],
            context: const AiRequestContext(apiKey: 'FAKE-KEY'),
          )
          .toList();
      final Future<void> assertion = expectLater(
        reading,
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.streamingTimeout,
          ),
        ),
      );
      await _pump();
      body.addError(TimeoutException('stream'));
      await body.close();
      await assertion;
      final AiDiagnosticEvent event = harness.diagnostics.events.last;
      expect(event.stage, AiRequestStage.stream);
      expect(event.exceptionType, 'TimeoutException');
    });

    test('malformed SSE and missing DONE are separate failures', () async {
      harness.transport.response(
        body: Stream<String>.value('data: {broken}\n\n'),
      );
      await expectFailure(AiFailureKind.malformedResponse);

      harness.transport.sse('partial answer', done: false);
      await expectFailure(AiFailureKind.streamInterrupted);
      expect(
        harness.diagnostics.events.last.tokensReceived,
        1,
        reason: 'Received text must be counted even when the stream is cut.',
      );
    });

    test('logs never contain the key, prompt or response content', () async {
      final String secretPrompt = 'PRIVATE PROMPT CONTENT 42';
      harness.transport.response(
        body: Stream<String>.value('data: ${jsonEncode(<String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'delta': <String, dynamic>{'content': 'SECRET ANSWER 99'},
                },
              ],
            })}\n\ndata: [DONE]\n\n'),
      );
      await harness.chat.send(secretPrompt);
      await _waitUntil(
        () => !harness.chat.state.isBusy && !harness.chat.state.hasError,
      );

      final String logText = harness.logger.state
          .map((AuraLogEntry entry) => '${entry.message} ${entry.context}')
          .join('\n');
      expect(logText, isNot(contains('FAKE-KEY')));
      expect(logText, isNot(contains(secretPrompt)));
      expect(logText, isNot(contains('SECRET ANSWER 99')));
      expect(logText, isNot(contains('Bearer')));
      expect(logText, isNot(contains('api.groq.com/openai')));
    });
  });

  group('Connection state and retry safety', () {
    test('verification success does not imply chat success', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.transport.response(
        body: Stream<String>.value('{"data":[]}'),
      );
      await harness.connection.test(providerId: 'groq');
      expect(
        harness.connection.state.status,
        AiConnectionStatus.connected,
      );
      expect(
        harness.connection.state.matches(_config()),
        isTrue,
      );

      harness.transport.error(
        const SocketException('Connection reset during chat'),
      );
      await harness.chat.send('why did this fail');
      await _waitUntil(() => harness.chat.state.hasError);

      expect(
        harness.chat.state.failureKind,
        AiFailureKind.networkFailure,
        reason:
            '${harness.chat.state.errorMessage} | ${harness.diagnostics.events.map((AiDiagnosticEvent event) => event.context).toList()}',
      );
      expect(
        harness.connection.state.status,
        AiConnectionStatus.connected,
        reason: 'A chat failure must not fabricate a /models failure.',
      );
      expect(AiChatStatus.failed.label, 'LAST CHAT FAILED');
    });

    test('changing configuration expires a previous verification', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.transport.response(
        body: Stream<String>.value('{"data":[]}'),
      );
      await harness.connection.test(providerId: 'groq');
      expect(harness.connection.state.status, AiConnectionStatus.connected);

      await harness.configs.upsert(
        _config(model: 'a-different-model'),
      );
      harness.connection.invalidate();
      expect(
        harness.connection.state.status,
        AiConnectionStatus.needsRefresh,
      );
      expect(
        harness.connection.state.matches(_config()),
        isFalse,
      );
    });

    test('retry after a transport failure does not duplicate the prompt',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.transport.error(const SocketException('reset'));
      await harness.chat.send('retry me');
      await _waitUntil(() => harness.chat.state.hasError);
      expect(harness.chat.state.failureKind, AiFailureKind.networkFailure);
      expect(
        harness.conversations.state.single
            .list()
            .where((AiMessage message) => message.role == AiMessageRole.user),
        hasLength(1),
      );

      harness.transport.sse('recovered answer');
      await harness.chat.retry();
      await _waitUntil(
        () => !harness.chat.state.isBusy && !harness.chat.state.hasError,
      );

      final List<AiMessage> messages =
          harness.conversations.state.single.list();
      expect(
        messages
            .where((AiMessage message) => message.role == AiMessageRole.user),
        hasLength(1),
      );
      expect(messages.last.content, 'recovered answer');
      expect(messages.last.isInterrupted, isFalse);
      expect(harness.chat.state.hasError, isFalse);
    });

    test('failed profiles stay isolated from each other', () async {
      final _Harness family = _Harness();
      final _Harness ayush = _Harness();
      await family.setUp(profile: AuraProfile.family);
      await ayush.setUp(profile: AuraProfile.ayush);
      addTearDown(family.tearDown);
      addTearDown(ayush.tearDown);

      family.transport.error(const SocketException('family failed'));
      await family.chat.send('family prompt');
      await _waitUntil(() => family.chat.state.hasError);

      expect(family.chat.state.failureKind, AiFailureKind.networkFailure);
      expect(ayush.chat.state.hasError, isFalse);
      expect(ayush.conversations.state, isEmpty);
      expect(
        family.credentials.profile.storageScope,
        isNot(ayush.credentials.profile.storageScope),
      );
    });
  });
}
