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
import 'package:aura_hub/features/ai/data/default_ai_context_assembler.dart';
import 'package:aura_hub/features/ai/data/default_ai_provider_registry.dart';
import 'package:aura_hub/features/ai/data/ollama_ai_adapter.dart';
import 'package:aura_hub/features/ai/data/openai_compatible_client.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_models.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_router.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_selection.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';

const String _apiKey = 'FAKE-PHASE5D-KEY';
const String _conversationMarker = 'AYUSH-ONLY-PROMPT-SHOULD-NOT-BE-SENT';

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

/// Records the exact provider request so tests can prove probes are metadata
/// only. No real HTTP client is used anywhere in this file.
class FakeTransport implements AiHttpTransport {
  final Queue<Object> _results = Queue<Object>();
  final List<AiHttpRequest> requests = <AiHttpRequest>[];
  final List<AiCancelToken?> tokens = <AiCancelToken?>[];

  void json(Object payload, {int statusCode = 200}) =>
      raw(jsonEncode(payload), statusCode: statusCode);

  void raw(String body, {int statusCode = 200}) {
    _results.add(
      AiHttpResponse(
        statusCode: statusCode,
        body: Stream<String>.value(body),
      ),
    );
  }

  void error(Object error) => _results.add(error);

  Completer<AiHttpResponse> defer() {
    final Completer<AiHttpResponse> completer = Completer<AiHttpResponse>();
    _results.add(completer.future);
    return completer;
  }

  void complete(
    Completer<AiHttpResponse> completer,
    Object payload, {
    int statusCode = 200,
  }) {
    if (completer.isCompleted) return;
    completer.complete(
      AiHttpResponse(
        statusCode: statusCode,
        body: Stream<String>.value(jsonEncode(payload)),
      ),
    );
  }

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    requests.add(request);
    tokens.add(cancelToken);
    if (_results.isEmpty) throw StateError('No scripted provider response.');
    final Object next = _results.removeFirst();
    if (next is AiHttpResponse) return next;
    if (next is Future<AiHttpResponse>) return next;
    throw next;
  }
}

/// Chat client that holds a stream open so provider switching can be tested
/// while a generation is genuinely active.
class ControlledChatClient implements AiClient {
  StreamController<String>? _stream;
  AiProviderConfig? lastConfig;
  AiCancelToken? lastToken;
  int callCount = 0;

  bool get isBusy => _stream != null && !_stream!.isClosed;

  void finish() {
    final StreamController<String>? stream = _stream;
    if (stream != null && !stream.isClosed) stream.close();
  }

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.auto,
    AiRequestContext? context,
  }) {
    callCount++;
    lastConfig = config;
    lastToken = context?.cancelToken;
    _stream = StreamController<String>();
    return _stream!.stream;
  }

  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {}
}

AiProviderConfig _groqConfig({
  String id = 'groq',
  String model = 'llama-3.3-70b-versatile',
  bool enabled = true,
  String baseUrl = 'https://api.groq.com/openai/v1',
}) =>
    AiProviderConfig(
      id: id,
      label: 'Groq',
      kind: AiProviderKind.openAiCompatible,
      baseUrl: baseUrl,
      model: model,
      enabled: enabled,
    );

AiProviderConfig _ollamaConfig({
  String id = 'ollama',
  String model = 'llama3.2',
  bool enabled = true,
  String baseUrl = OllamaAiAdapter.defaultBaseUrl,
}) =>
    AiProviderConfig(
      id: id,
      label: 'Local Ollama',
      kind: AiProviderKind.localOllama,
      baseUrl: baseUrl,
      model: model,
      enabled: enabled,
    );

Future<void> _waitUntil(
  bool Function() ready, {
  String message = 'Expected asynchronous AI work to finish.',
}) async {
  for (int attempt = 0; attempt < 500; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail(message);
}

class _Harness {
  late Directory directory;
  late FakeTransport groqTransport;
  late FakeTransport ollamaTransport;
  late MemoryVault vault;
  late AuraLogger logger;
  late AiConfigController configs;
  late AiPreferencesController preferences;
  late AiCredentialController credentials;
  late AiConversationLibraryController conversations;
  late AiConnectionController connection;
  late AiProviderRouter router;
  late ControlledChatClient chatClient;
  late AiChatController chat;
  late AiProviderSwitchCoordinator switcher;
  late ProfileAccess access;

  Future<void> setUp({
    AuraProfile profile = AuraProfile.family,
    bool storeKey = true,
  }) async {
    directory = await Directory.systemTemp.createTemp('aura_ai_management_');
    groqTransport = FakeTransport();
    ollamaTransport = FakeTransport();
    vault = MemoryVault();
    logger = AuraLogger();

    final ProfileSession session = ProfileSession(
      profile: profile,
      startedAt: DateTime(1970),
      authenticated: profile == AuraProfile.ayush,
    );
    access = ProfileAccess(session);

    ProfileAccess accessReader() => access;

    configs = AiConfigController(
      profile: profile,
      store: AiConfigStore(directory: directory, profile: profile),
      logger: logger,
    );
    await configs.load();
    // upsert() prepends, so insert Ollama first to keep Groq as the first
    // enabled provider used by fallback-selection assertions.
    await configs.upsert(_ollamaConfig());
    await configs.upsert(_groqConfig());

    preferences = AiPreferencesController(
      profile: profile,
      store: AiPreferencesStore(directory: directory, profile: profile),
      accessReader: accessReader,
    );
    await preferences.load();
    await preferences.selectProvider('groq');

    credentials = AiCredentialController(
      profile: profile,
      store: AiCredentialStore(vault: vault),
    );
    if (storeKey) {
      await credentials.save(providerId: 'groq', apiKey: _apiKey);
    }

    conversations = AiConversationLibraryController(
      profile: profile,
      storage: profile == AuraProfile.family
          ? AiConversationStore(directory: directory, profile: profile)
          : InMemoryAiConversationStorage(),
      accessReader: accessReader,
    );
    await conversations.load();

    router = AiProviderRouter(
      registry: DefaultAiProviderRegistry(<AiProviderAdapter>[
        OpenAiCompatibleAiClient(transport: groqTransport),
        OllamaAiAdapter(transport: ollamaTransport),
      ]),
    );
    connection = AiConnectionController(
      configs: configs,
      credentials: credentials,
      client: router,
      logger: logger,
      router: router,
    );

    chatClient = ControlledChatClient();
    chat = AiChatController(
      profile: profile,
      access: access,
      accessReader: accessReader,
      configs: configs,
      preferences: preferences,
      conversations: conversations,
      credentials: credentials,
      client: chatClient,
      logger: logger,
      contextAssembler: const DefaultAiContextAssembler(),
    );
    switcher = AiProviderSwitchCoordinator(
      chat: chat,
      preferences: preferences,
      connection: connection,
      credentials: credentials,
    );
  }

  Future<void> tearDown() async {
    chatClient.finish();
    chat.dispose();
    connection.dispose();
    conversations.dispose();
    credentials.dispose();
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
  group('Provider selection', () {
    test('explicit provider selection is restored from scoped preferences',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      expect(
        AiProviderSelection.effective(
                harness.configs.state, harness.preferences.state)
            ?.id,
        'groq',
      );
      await harness.preferences.selectProvider('ollama');
      expect(
        AiProviderSelection.effective(
                harness.configs.state, harness.preferences.state)
            ?.id,
        'ollama',
      );

      final AiPreferences reloaded = await AiPreferencesStore(
        directory: harness.directory,
        profile: AuraProfile.family,
      ).load();
      expect(reloaded.selectedProviderId, 'ollama');
      expect(reloaded.consentGranted, isFalse);
      expect(
        File('${harness.directory.path}${Platform.pathSeparator}ai_preferences_family.json')
            .existsSync(),
        isTrue,
      );
    });

    test('invalid selection never invents a provider or silently falls back',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      await harness.preferences.selectProvider('missing-provider');
      expect(
        AiProviderSelection.effective(
                harness.configs.state, harness.preferences.state)
            ?.id,
        'groq',
        reason: 'An unknown id resolves to the first enabled provider.',
      );

      await harness.configs.upsert(_groqConfig(enabled: false));
      await harness.preferences.selectProvider('groq');
      expect(
        AiProviderSelection.effective(
          harness.configs.state,
          harness.preferences.state,
        ),
        isNull,
        reason:
            'A disabled explicit selection must block requests, not fall back.',
      );
    });

    test('invalid model ids are rejected and a valid id persists without a key',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      expect(await harness.configs.selectModel('groq', '   '), isFalse);
      expect(await harness.configs.selectModel('groq', 'bad model!'), isFalse);
      expect(await harness.configs.selectModel('groq', 'x' * 201), isFalse);
      expect(await harness.configs.selectModel('missing', 'model'), isFalse);
      expect(
        AiProviderSelection.byId(harness.configs.state, 'groq')!.model,
        'llama-3.3-70b-versatile',
      );

      expect(
        await harness.configs.selectModel('groq', 'llama-3.1-8b-instant'),
        isTrue,
      );
      expect(
        AiProviderSelection.byId(harness.configs.state, 'groq')!.model,
        'llama-3.1-8b-instant',
      );
      final String configJson = File(
        '${harness.directory.path}${Platform.pathSeparator}ai_providers_family.json',
      ).readAsStringSync();
      expect(configJson, contains('llama-3.1-8b-instant'));
      expect(configJson, isNot(contains(_apiKey)));
    });

    test('unsupported providers are not accepted for discovery', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      final AiProviderConfig gemini = _groqConfig(id: 'gemini').copyWith(
        kind: AiProviderKind.googleGemini,
        label: 'Gemini',
      );
      await harness.connection.discoverModels(gemini);
      final AiModelCatalogEntry catalog =
          harness.connection.modelsFor('gemini');
      expect(catalog.status, AiModelLoadStatus.error);
      expect(catalog.message, AiProviderManagementMessages.unsupported);
      expect(harness.groqTransport.requests, isEmpty);
    });
  });

  group('Model discovery and selection', () {
    test('Groq discovery uses authenticated metadata only', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.groqTransport.json(<String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{
            'id': 'llama-3.1-8b-instant',
            'name': 'Llama 3.1 8B',
            'owned_by': 'groq',
            'context_window': 131072,
            'secret': 'DROP-THIS-FIELD',
          },
        ],
      });
      await harness.connection.discoverModels(_groqConfig(model: ''));

      final AiModelCatalogEntry catalog = harness.connection.modelsFor('groq');
      expect(catalog.status, AiModelLoadStatus.loaded);
      expect(catalog.models, hasLength(1));
      expect(catalog.models.single.id, 'llama-3.1-8b-instant');
      expect(catalog.models.single.label, 'Llama 3.1 8B');
      expect(catalog.models.single.contextWindow, 131072);
      expect(
          catalog.models.single.toString(), isNot(contains('DROP-THIS-FIELD')));

      final AiHttpRequest request = harness.groqTransport.requests.single;
      expect(request.method, AiHttpMethod.get);
      expect(request.uri.path, endsWith('/models'));
      expect(request.body, isNull);
      expect(request.headers['Authorization'], 'Bearer $_apiKey');
      expect(jsonEncode(request.headers), isNot(contains(_conversationMarker)));
    });

    test('Ollama discovery uses /api/tags without a credential', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.ollamaTransport.json(<String, dynamic>{
        'models': <dynamic>[
          <String, dynamic>{
            'name': 'llama3.2:latest',
            'model': 'llama3.2:latest',
            'size': 1000,
            'digest': 'sha256:abc',
            'internal': 'DROP-THIS-FIELD',
          },
        ],
      });
      await harness.connection.refreshModels(providerId: 'ollama');

      final AiModelCatalogEntry catalog =
          harness.connection.modelsFor('ollama');
      expect(catalog.status, AiModelLoadStatus.loaded);
      expect(catalog.models.single.id, 'llama3.2:latest');
      expect(catalog.models.single.label, 'llama3.2:latest');

      final AiHttpRequest request = harness.ollamaTransport.requests.single;
      expect(request.method, AiHttpMethod.get);
      expect(request.uri.path, endsWith('/api/tags'));
      expect(request.body, isNull);
      expect(request.headers.containsKey('Authorization'), isFalse);
    });

    test('running Ollama with no models reports an honest empty state',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.ollamaTransport.json(<String, dynamic>{
        'models': <dynamic>[],
      });
      await harness.connection.refreshModels(providerId: 'ollama');

      final AiModelCatalogEntry catalog =
          harness.connection.modelsFor('ollama');
      expect(catalog.status, AiModelLoadStatus.noModels);
      expect(catalog.models, isEmpty);
      expect(catalog.message, contains(AiProviderManagementMessages.noModels));
      expect(
        catalog.message,
        contains(AiProviderManagementMessages.selectedModelMissing),
      );
    });

    test('malformed and duplicate metadata cannot fabricate model entries',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.groqTransport.json(<String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'id': 'same'},
          <String, dynamic>{'id': 'same'},
        ],
      });
      await harness.connection.refreshModels(providerId: 'groq');
      expect(
          harness.connection.modelsFor('groq').status, AiModelLoadStatus.error);
      expect(harness.connection.modelsFor('groq').failureKind,
          AiFailureKind.malformedResponse);
      expect(harness.connection.modelsFor('groq').models, isEmpty);

      harness.groqTransport.raw('not-json');
      await harness.connection.refreshModels(providerId: 'groq');
      expect(
          harness.connection.modelsFor('groq').status, AiModelLoadStatus.error);
      expect(harness.connection.modelsFor('groq').models, isEmpty);
    });

    test(
        'a disappeared selected model asks for a new choice without substituting',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.groqTransport.json(<String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'id': 'new-model'},
        ],
      });
      await harness.connection.refreshModels(providerId: 'groq');

      final AiModelCatalogEntry catalog = harness.connection.modelsFor('groq');
      expect(catalog.status, AiModelLoadStatus.loaded);
      expect(catalog.models.single.id, 'new-model');
      expect(
          catalog.message, AiProviderManagementMessages.selectedModelMissing);
      expect(
        AiProviderSelection.byId(harness.configs.state, 'groq')!.model,
        'llama-3.3-70b-versatile',
      );
    });

    test('a valid model selection survives a later refresh', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      expect(
        await harness.configs.selectModel('groq', 'llama-3.1-8b-instant'),
        isTrue,
      );
      harness.groqTransport.json(<String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'id': 'llama-3.1-8b-instant'},
        ],
      });
      await harness.connection.refreshModels(providerId: 'groq');

      expect(harness.connection.modelsFor('groq').message, isNull);
      expect(
        AiProviderSelection.byId(harness.configs.state, 'groq')!.model,
        'llama-3.1-8b-instant',
      );
    });

    test('Ollama hostname endpoints are rejected before any request', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      await harness.connection.discoverModels(
        _ollamaConfig(baseUrl: 'http://localhost:11434'),
      );
      final AiModelCatalogEntry catalog =
          harness.connection.modelsFor('ollama');
      expect(catalog.status, AiModelLoadStatus.error);
      expect(catalog.message, AiProviderManagementMessages.configuration);
      expect(harness.ollamaTransport.requests, isEmpty);
    });
  });

  group('Connection testing', () {
    test('a successful cloud test reports metadata only for that provider',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.groqTransport.json(<String, dynamic>{
        'data': <dynamic>[],
      });
      await harness.connection.test(providerId: 'groq');

      final AiConnectionState status = harness.connection.statusFor('groq');
      expect(status.status, AiConnectionStatus.connected);
      expect(status.matches(_groqConfig()), isTrue);
      expect(status.message, contains('/models'));
      expect(harness.connection.statusFor('ollama').status,
          AiConnectionStatus.unknown);
      expect(harness.groqTransport.requests.single.body, isNull);
      expect(
          harness.groqTransport.requests.single.uri.path, endsWith('/models'));
    });

    test('a successful local test uses /api/tags and sends no key', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.ollamaTransport.json(<String, dynamic>{
        'models': <dynamic>[],
      });
      await harness.connection.test(providerId: 'ollama');

      expect(harness.connection.statusFor('ollama').status,
          AiConnectionStatus.connected);
      expect(harness.connection.statusFor('ollama').message,
          contains('Local provider'));
      final AiHttpRequest request = harness.ollamaTransport.requests.single;
      expect(request.uri.path, endsWith('/api/tags'));
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.body, isNull);
    });

    test('authentication failures classify safely without echoing a body',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.groqTransport.raw('SECRET-RESPONSE-BODY', statusCode: 401);
      await harness.connection.test(providerId: 'groq');

      final AiConnectionState status = harness.connection.statusFor('groq');
      expect(status.status, AiConnectionStatus.error);
      expect(status.failureKind, AiFailureKind.authentication);
      expect(status.message, isNot(contains('SECRET-RESPONSE-BODY')));
    });

    test('network and timeout failures use the typed failure taxonomy',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.groqTransport.error(SocketException('Connection refused'));
      await harness.connection.test(providerId: 'groq');
      expect(harness.connection.statusFor('groq').failureKind,
          AiFailureKind.networkFailure);

      harness.groqTransport.error(
        TimeoutException('operation timed out', const Duration(seconds: 20)),
      );
      await harness.connection.test(providerId: 'groq');
      expect(harness.connection.statusFor('groq').failureKind,
          AiFailureKind.connectionTimeout);
      expect(
        harness.connection.statusFor('groq').message,
        isNot(contains('operation timed out')),
      );
    });

    test('missing cloud credentials block a test before any request', () async {
      final _Harness harness = _Harness();
      await harness.setUp(storeKey: false);
      addTearDown(harness.tearDown);

      await harness.connection.test(providerId: 'groq');

      expect(harness.connection.statusFor('groq').status,
          AiConnectionStatus.error);
      expect(harness.connection.statusFor('groq').message,
          contains('Add an API key'));
      expect(harness.groqTransport.requests, isEmpty);
    });

    test('overlapping tests for the same provider are ignored', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      final Completer<AiHttpResponse> first = harness.groqTransport.defer();
      final Future<void> firstTest =
          harness.connection.test(providerId: 'groq');
      await _waitUntil(() => harness.groqTransport.requests.length == 1);

      final Future<void> secondTest =
          harness.connection.test(providerId: 'groq');
      expect(harness.groqTransport.requests, hasLength(1));

      harness.groqTransport.complete(first, <String, dynamic>{
        'data': <dynamic>[],
      });
      await Future.wait<void>(<Future<void>>[firstTest, secondTest]);

      expect(harness.groqTransport.requests, hasLength(1));
      expect(harness.connection.statusFor('groq').status,
          AiConnectionStatus.connected);
    });

    test('rapid provider switching ignores a stale provider result', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      final Completer<AiHttpResponse> groqCall = harness.groqTransport.defer();
      final Completer<AiHttpResponse> ollamaCall =
          harness.ollamaTransport.defer();
      final Future<void> groqTest = harness.connection.test(providerId: 'groq');
      await _waitUntil(() => harness.groqTransport.requests.length == 1);
      final Future<void> ollamaTest =
          harness.connection.test(providerId: 'ollama');
      await _waitUntil(() => harness.ollamaTransport.requests.length == 1);

      harness.ollamaTransport.complete(ollamaCall, <String, dynamic>{
        'models': <dynamic>[],
      });
      await ollamaTest;
      expect(harness.connection.state.verifiedProviderId, 'ollama');

      harness.groqTransport.complete(groqCall, <String, dynamic>{
        'data': <dynamic>[],
      });
      await groqTest;
      expect(harness.connection.statusFor('groq').status,
          AiConnectionStatus.connected);
      expect(harness.connection.state.verifiedProviderId, 'ollama');
    });

    test('cancelling a test discards a late successful response', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      final Completer<AiHttpResponse> pending = harness.groqTransport.defer();
      final Future<void> probe = harness.connection.test(providerId: 'groq');
      await _waitUntil(() => harness.groqTransport.requests.length == 1);

      harness.connection.cancel(providerId: 'groq');
      expect(harness.groqTransport.tokens.single!.isCancelled, isTrue);

      harness.groqTransport.complete(pending, <String, dynamic>{
        'data': <dynamic>[],
      });
      await probe;

      expect(harness.connection.statusFor('groq').status,
          AiConnectionStatus.error);
      expect(harness.connection.statusFor('groq').failureKind,
          AiFailureKind.cancelled);
    });

    test('lock discards status and ignores stale discovery responses',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      final Completer<AiHttpResponse> pending = harness.groqTransport.defer();
      final Future<void> discovery =
          harness.connection.discoverModels(_groqConfig());
      await _waitUntil(() => harness.groqTransport.requests.length == 1);

      harness.connection.discardForLock();
      harness.groqTransport.complete(pending, <String, dynamic>{
        'data': <dynamic>[
          <String, dynamic>{'id': 'late-model'},
        ],
      });
      await discovery;

      expect(
          harness.connection.modelsFor('groq').status, AiModelLoadStatus.idle);
      expect(harness.connection.modelsFor('groq').models, isEmpty);
      expect(harness.connection.statusFor('groq').status,
          AiConnectionStatus.unknown);
    });

    test('a local failure never falls back to the cloud provider', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      harness.ollamaTransport.error(
        const AiException(
          AiFailureKind.networkFailure,
          'Local server unavailable.',
        ),
      );
      await harness.connection.test(providerId: 'ollama');

      expect(harness.connection.statusFor('ollama').status,
          AiConnectionStatus.error);
      expect(harness.connection.state.verifiedProviderId, isNull);
      expect(harness.groqTransport.requests, isEmpty);
    });
  });

  group('Security, consent and profile isolation', () {
    test('the vault target is scoped and raw keys never enter JSON files',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      expect(vaultKeyTargets(harness.vault), <String>{
        'AURA_HUB/AI/family/groq',
      });
      expect(harness.credentials.state.presence, AiCredentialPresence.present);

      final String preferencesJson = File(
        '${harness.directory.path}${Platform.pathSeparator}ai_preferences_family.json',
      ).readAsStringSync();
      final String configJson = File(
        '${harness.directory.path}${Platform.pathSeparator}ai_providers_family.json',
      ).readAsStringSync();
      expect(preferencesJson, isNot(contains(_apiKey)));
      expect(configJson, isNot(contains(_apiKey)));
      final AiConnectionState state = harness.connection.state;
      expect(
        jsonEncode(<String, Object?>{
          'status': state.status.name,
          'message': state.message,
          'providerId': state.verifiedProviderId,
          'signature': state.verifiedSignature,
        }),
        isNot(contains(_apiKey)),
      );
    });

    test('FAMILY cannot read AYUSH credentials from the same vault', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      final AiCredentialStore familyStore =
          AiCredentialStore(vault: harness.vault);
      final AiCredentialStore ayushStore =
          AiCredentialStore(vault: harness.vault);
      await familyStore.save(
        profileScope: AuraProfile.family.storageScope,
        providerId: 'groq',
        apiKey: 'FAMILY-KEY',
      );
      await ayushStore.save(
        profileScope: AuraProfile.ayush.storageScope,
        providerId: 'groq',
        apiKey: 'AYUSH-KEY',
      );

      expect(harness.vault.secrets, hasLength(2));
      expect(
        await familyStore.readSecret(
          profileScope: AuraProfile.family.storageScope,
          providerId: 'groq',
        ),
        'FAMILY-KEY',
      );
      expect(
        await ayushStore.readSecret(
          profileScope: AuraProfile.ayush.storageScope,
          providerId: 'groq',
        ),
        'AYUSH-KEY',
      );
      expect(
        harness.vault.secrets.keys,
        containsAll(<String>[
          'AURA_HUB/AI/family/groq',
          'AURA_HUB/AI/ayush/groq',
        ]),
      );
    });

    test('switching providers never grants consent and chat stays blocked',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      expect(harness.preferences.state.consentGranted, isFalse);
      await harness.switcher.switchTo('ollama');
      expect(harness.preferences.state.selectedProviderId, 'ollama');
      expect(harness.preferences.state.consentGranted, isFalse);

      await harness.chat.send(_conversationMarker);
      expect(harness.chat.state.failureKind, AiFailureKind.consentRequired);
      expect(harness.chatClient.callCount, 0);
      expect(harness.groqTransport.requests, isEmpty);
      expect(harness.ollamaTransport.requests, isEmpty);
    });

    test('revoking consent blocks subsequent external requests', () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      await harness.preferences.setConsent(true);
      final Future<void> firstSend = harness.chat.send('hello');
      await _waitUntil(() => harness.chatClient.callCount == 1);
      harness.chatClient.finish();
      await firstSend;

      await harness.preferences.setConsent(false);
      await harness.chat.send('second message');
      expect(harness.chat.state.failureKind, AiFailureKind.consentRequired);
      expect(harness.chatClient.callCount, 1);
    });

    test('switching during generation cancels it and preserves history',
        () async {
      final _Harness harness = _Harness();
      await harness.setUp();
      addTearDown(harness.tearDown);

      await harness.preferences.setConsent(true);
      final Future<void> send = harness.chat.send(_conversationMarker);
      await _waitUntil(
        () => harness.chatClient.callCount == 1 && harness.chat.isBusy,
      );

      await harness.switcher.switchTo('ollama');

      expect(harness.chatClient.lastToken?.isCancelled, isTrue);
      expect(harness.preferences.state.selectedProviderId, 'ollama');
      expect(harness.conversations.state, isNotEmpty);
      harness.chatClient.finish();
      await send;
      expect(
        harness.conversations.state.single
            .list()
            .any((AiMessage message) => message.content == _conversationMarker),
        isTrue,
      );
    });
  });
}

Set<String> vaultKeyTargets(MemoryVault vault) => vault.secrets.keys.toSet();
