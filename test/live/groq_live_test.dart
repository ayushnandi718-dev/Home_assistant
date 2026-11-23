import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/ai_preferences_store.dart';
import 'package:aura_hub/features/ai/data/default_ai_context_assembler.dart';
import 'package:aura_hub/features/ai/data/openai_compatible_client.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_diagnostics.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';

// ---------------------------------------------------------------------------
// Opt-in gates. Safe by default: no live test body can run unless explicitly
// enabled, and transmitting a prompt requires a second, separate confirmation.
// ---------------------------------------------------------------------------

const String metadataGate = 'AURA_ENABLE_LIVE_GROQ_TESTS';
const String chatGate = 'AURA_CONFIRM_LIVE_GROQ_CHAT';

const String _mockKey = 'FAKE-LIVE-GROQ-KEY-NOT-A-SECRET';
const String _rawBodyMarker = 'RAW-PROVIDER-BODY-MUST-NOT-BE-SHOWN';
const String _syntheticPrompt =
    'Phase 5E connectivity check. Reply with OK only.';

bool groqLiveGateEnabledIn(Map<String, String> environment, String name) {
  final String? fromEnvironment = environment[name];
  if (fromEnvironment == null) return false;
  final String value = fromEnvironment.trim().toLowerCase();
  return value == 'true' || value == '1';
}

bool groqLiveChatEligibleIn(Map<String, String> environment) =>
    groqLiveGateEnabledIn(environment, metadataGate) &&
    groqLiveGateEnabledIn(environment, chatGate);

bool _gateEnabled(String name) {
  if (groqLiveGateEnabledIn(Platform.environment, name)) return true;
  if (name == metadataGate) {
    return const bool.fromEnvironment(metadataGate, defaultValue: false);
  }
  if (name == chatGate) {
    return const bool.fromEnvironment(chatGate, defaultValue: false);
  }
  return false;
}

String get _metadataSkipReason =>
    '$metadataGate=true is required to contact api.groq.com.';

String get _chatSkipReason =>
    '$metadataGate=true and $chatGate=true are both required to send a prompt.';

AiProviderConfig _groqConfig({String model = 'test-model'}) => AiProviderConfig(
      id: 'groq-live-test',
      label: 'Groq live test',
      kind: AiProviderKind.openAiCompatible,
      baseUrl: 'https://api.groq.com/openai/v1',
      model: model,
      enabled: true,
    );

/// Non-secret request context for mocked transport failures. The adapter
/// validates credentials before it calls the transport, so a fake key must be
/// injected here; no credential vault or real API key is involved.
AiRequestContext _mockContext({AiCancelToken? cancelToken}) => AiRequestContext(
      apiKey: _mockKey,
      cancelToken: cancelToken,
    );

class _ScriptedTransport implements AiHttpTransport {
  final Queue<Object> _results = Queue<Object>();
  final List<AiHttpRequest> requests = <AiHttpRequest>[];
  final void Function(AiCancelToken?)? onSend;

  _ScriptedTransport({this.onSend});

  void jsonResponse(Object payload, {int statusCode = 200}) =>
      rawResponse(jsonEncode(payload), statusCode: statusCode);

  void rawResponse(String body, {int statusCode = 200}) => _results.add(
        AiHttpResponse(
          statusCode: statusCode,
          body: Stream<String>.value(body),
        ),
      );

  void error(Object error) => _results.add(error);

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    requests.add(request);
    onSend?.call(cancelToken);
    if (_results.isEmpty) throw StateError('No scripted provider response.');
    final Object next = _results.removeFirst();
    if (next is AiHttpResponse) return next;
    throw next;
  }
}

class _RecordingDiagnostics extends AiDiagnostics {
  final List<Map<String, String>> contexts = <Map<String, String>>[];

  @override
  void record(AiDiagnosticEvent event) => contexts.add(event.context);

  String get serialized => jsonEncode(contexts);
}

class _CountingChatClient implements AiClient {
  int calls = 0;

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.auto,
    AiRequestContext? context,
  }) async* {
    calls++;
    yield 'OK';
  }

  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {}
}

Future<AiException> _aiException(Future<void> Function() action) async {
  try {
    await action();
  } on AiException catch (error) {
    return error;
  }
  fail('Expected an AiException.');
}

Directory _isolatedDirectory() {
  final Directory directory =
      Directory.systemTemp.createTempSync('aura_live_groq_safety_');
  final String appData = LocalPaths.appData().path;
  assert(!directory.path.startsWith(appData));
  return directory;
}

/// Reads only non-secret configuration to resolve the currently selected Groq
/// provider. No provider id or model id is hardcoded from the audit snapshot.
Future<AiProviderConfig> _resolveConfiguredGroq() async {
  final List<AiProviderConfig> configs = await AiConfigStore(
    directory: LocalPaths.appData(),
    profile: AuraProfile.family,
  ).load();

  for (final AiProviderConfig config in configs) {
    if (!config.enabled ||
        config.kind != AiProviderKind.openAiCompatible ||
        !config.baseUrl.contains('api.groq.com')) {
      continue;
    }
    return config;
  }
  fail('No enabled Groq provider configuration found in the FAMILY workspace.');
}

Future<AiCredentialStore> _requireCredential(AiProviderConfig config) async {
  final AiCredentialStore store = AiCredentialStore();
  final bool present = await store.has(
    profileScope: AuraProfile.family.storageScope,
    providerId: config.id,
  );
  if (!present) {
    // The target is an identifier, never the secret.
    fail('No stored Groq credential. Expected target: '
        '${store.targetFor(
      profileScope: AuraProfile.family.storageScope,
      providerId: config.id,
    )}. Add the key through AURA secure settings.');
  }
  return store;
}

void main() {
  group('MOCK VERIFIED — Groq live-harness safety', () {
    test('live gate evaluation is deterministic from injected environment', () {
      // Default/absent gates must not enable live execution regardless of the
      // real process environment (an operator may set live gates for other runs).
      expect(groqLiveGateEnabledIn(const <String, String>{}, metadataGate),
          isFalse);
      expect(
          groqLiveGateEnabledIn(const <String, String>{}, chatGate), isFalse);
      expect(groqLiveChatEligibleIn(const <String, String>{}), isFalse);

      const Map<String, String> bothFalse = <String, String>{
        metadataGate: 'false',
        chatGate: 'false',
      };
      expect(groqLiveGateEnabledIn(bothFalse, metadataGate), isFalse);
      expect(groqLiveGateEnabledIn(bothFalse, chatGate), isFalse);
      expect(groqLiveChatEligibleIn(bothFalse), isFalse);

      const Map<String, String> metadataOnly = <String, String>{
        metadataGate: 'true',
      };
      expect(groqLiveGateEnabledIn(metadataOnly, metadataGate), isTrue);
      expect(groqLiveGateEnabledIn(metadataOnly, chatGate), isFalse);
      expect(groqLiveChatEligibleIn(metadataOnly), isFalse);

      const Map<String, String> chatOnly = <String, String>{
        chatGate: 'true',
      };
      expect(groqLiveGateEnabledIn(chatOnly, metadataGate), isFalse);
      expect(groqLiveGateEnabledIn(chatOnly, chatGate), isTrue);
      expect(groqLiveChatEligibleIn(chatOnly), isFalse);

      const Map<String, String> bothTrue = <String, String>{
        metadataGate: 'true',
        chatGate: 'true',
      };
      expect(groqLiveGateEnabledIn(bothTrue, metadataGate), isTrue);
      expect(groqLiveGateEnabledIn(bothTrue, chatGate), isTrue);
      expect(groqLiveChatEligibleIn(bothTrue), isTrue);

      expect(_metadataSkipReason, contains(metadataGate));
      expect(_chatSkipReason, contains(chatGate));
    });

    test('isolated fixtures never point at real AURA app data', () {
      final Directory directory = _isolatedDirectory();
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      expect(directory.path, isNot(LocalPaths.appData().path));
      expect(
        directory.path.startsWith(Directory.systemTemp.path),
        isTrue,
        reason: 'Cleanup is confined to the system temp directory.',
      );
    });

    test('credential targets are dynamic and profile scoped', () async {
      final AiCredentialStore store = AiCredentialStore();
      final String family = store.targetFor(
        profileScope: AuraProfile.family.storageScope,
        providerId: 'provider-example',
      );
      final String ayush = store.targetFor(
        profileScope: AuraProfile.ayush.storageScope,
        providerId: 'provider-example',
      );

      expect(family, 'AURA_HUB/AI/family/provider-example');
      expect(ayush, 'AURA_HUB/AI/ayush/provider-example');
      expect(family, isNot(ayush));
    });

    test('HTTP 401 classifies as authentication without echoing the body',
        () async {
      final _ScriptedTransport transport = _ScriptedTransport()
        ..rawResponse(_rawBodyMarker, statusCode: 401);
      final OpenAiCompatibleAiClient client = OpenAiCompatibleAiClient(
        transport: transport,
      );

      final AiException error = await _aiException(
        () => client
            .listModels(config: _groqConfig(), context: _mockContext())
            .then((_) {}),
      );
      expect(error.kind, AiFailureKind.authentication);
      expect(error.message, isNot(contains(_rawBodyMarker)));
      expect(transport.requests.single.body, isNull);
    });

    test('HTTP 429 classifies as rate limited', () async {
      final _ScriptedTransport transport = _ScriptedTransport()
        ..rawResponse(_rawBodyMarker, statusCode: 429);
      final OpenAiCompatibleAiClient client = OpenAiCompatibleAiClient(
        transport: transport,
      );

      final AiException error = await _aiException(
        () => client
            .listModels(config: _groqConfig(), context: _mockContext())
            .then((_) {}),
      );
      expect(error.kind, AiFailureKind.rateLimited);
      expect(error.message, isNot(contains(_rawBodyMarker)));
    });

    test('timeout and socket failures use the typed taxonomy', () async {
      final _ScriptedTransport timeouts = _ScriptedTransport()
        ..error(TimeoutException('raw timeout detail'));
      final OpenAiCompatibleAiClient timeoutClient = OpenAiCompatibleAiClient(
        transport: timeouts,
      );
      final AiException timeoutError = await _aiException(
        () => timeoutClient
            .listModels(config: _groqConfig(), context: _mockContext())
            .then((_) {}),
      );
      expect(timeoutError.kind, AiFailureKind.connectionTimeout);
      expect(timeoutError.message, isNot(contains('raw timeout detail')));

      final _ScriptedTransport sockets = _ScriptedTransport()
        ..error(const SocketException('raw socket detail'));
      final OpenAiCompatibleAiClient socketClient = OpenAiCompatibleAiClient(
        transport: sockets,
      );
      final AiException socketError = await _aiException(
        () => socketClient
            .listModels(config: _groqConfig(), context: _mockContext())
            .then((_) {}),
      );
      expect(socketError.kind, AiFailureKind.networkFailure);
      expect(socketError.message, isNot(contains('raw socket detail')));
    });

    test('cancellation produces no fabricated model list', () async {
      final AiCancelToken token = AiCancelToken();
      final _ScriptedTransport transport = _ScriptedTransport(
        onSend: (AiCancelToken? sentToken) {
          expect(sentToken, same(token));
          sentToken?.cancel();
        },
      )..jsonResponse(<String, dynamic>{
          'data': <dynamic>[
            <String, dynamic>{'id': 'must-not-appear'}
          ],
        });
      final OpenAiCompatibleAiClient client = OpenAiCompatibleAiClient(
        transport: transport,
      );

      final AiException error = await _aiException(
        () => client
            .listModels(
              config: _groqConfig(),
              context: _mockContext(cancelToken: token),
            )
            .then((_) {}),
      );
      expect(error.kind, AiFailureKind.cancelled);
    });

    test('keys and prompts never enter diagnostics or safe context', () async {
      final _RecordingDiagnostics diagnostics = _RecordingDiagnostics();
      final _ScriptedTransport transport = _ScriptedTransport()
        ..rawResponse(_rawBodyMarker, statusCode: 401);
      final OpenAiCompatibleAiClient client = OpenAiCompatibleAiClient(
        transport: transport,
        diagnostics: diagnostics,
      );
      final AiRequestContext context = AiRequestContext(apiKey: _mockKey);

      final AiException error = await _aiException(
        () => client
            .listModels(config: _groqConfig(), context: context)
            .then((_) {}),
      );

      expect(context.safeContext.containsKey('apiKey'), isFalse);
      expect(context.safeContext.values, isNot(contains(_mockKey)));
      expect(diagnostics.serialized, isNot(contains(_mockKey)));
      expect(diagnostics.serialized, isNot(contains(_rawBodyMarker)));
      expect(error.toString(), isNot(contains(_mockKey)));
      expect(transport.requests.single.toString(), isNot(contains(_mockKey)));
    });

    test('consent is still enforced by the real chat controller', () async {
      final Directory directory = _isolatedDirectory();
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      final AuraLogger logger = AuraLogger();
      ProfileAccess accessReader() => ProfileAccess(ProfileSession.initial);
      final AiConfigController configs = AiConfigController(
        profile: AuraProfile.family,
        store: AiConfigStore(directory: directory, profile: AuraProfile.family),
        logger: logger,
        accessReader: accessReader,
      );
      await configs.load();
      await configs.upsert(_groqConfig());

      final AiPreferencesController preferences = AiPreferencesController(
        profile: AuraProfile.family,
        store: AiPreferencesStore(
          directory: directory,
          profile: AuraProfile.family,
        ),
        accessReader: accessReader,
      );
      await preferences.load();
      await preferences.selectProvider('groq-live-test');

      final AiConversationLibraryController conversations =
          AiConversationLibraryController(
        profile: AuraProfile.family,
        storage: AiConversationStore(
          directory: directory,
          profile: AuraProfile.family,
        ),
        accessReader: accessReader,
      );
      await conversations.load();

      final _CountingChatClient client = _CountingChatClient();
      final AiChatController chat = AiChatController(
        profile: AuraProfile.family,
        access: ProfileAccess(ProfileSession.initial),
        accessReader: accessReader,
        configs: configs,
        preferences: preferences,
        conversations: conversations,
        credentials: AiCredentialController(
          profile: AuraProfile.family,
          store: AiCredentialStore(),
          accessReader: accessReader,
        ),
        client: client,
        logger: logger,
        contextAssembler: const DefaultAiContextAssembler(),
      );
      addTearDown(chat.dispose);

      expect(preferences.state.consentGranted, isFalse);
      await chat.send(_syntheticPrompt);
      expect(chat.state.failureKind, AiFailureKind.consentRequired);
      expect(client.calls, 0);
      expect(conversations.state, isEmpty);
    });
  });

  group('LIVE VERIFIED — Groq metadata (explicit opt-in)', () {
    test('real authenticated model discovery', () async {
      final AiProviderConfig config = await _resolveConfiguredGroq();
      final AiCredentialStore store = await _requireCredential(config);
      final String? key = await store.readSecret(
        profileScope: AuraProfile.family.storageScope,
        providerId: config.id,
      );
      if (key == null || key.isEmpty) {
        fail('Credential for the resolved target was empty.');
      }

      final OpenAiCompatibleAiClient client = OpenAiCompatibleAiClient(
        transport: const DartIoAiHttpTransport(),
        diagnostics: const NoAiDiagnostics(),
      );
      final List<AiModelInfo> models = await client.listModels(
        config: config,
        context: AiRequestContext(apiKey: key),
      );

      expect(models, isNotEmpty);
      final bool selectedStillAvailable =
          models.any((AiModelInfo model) => model.id == config.model);
      if (!selectedStillAvailable) {
        fail('Configured model "${config.model}" is not in the live catalogue. '
            'Discovered ${models.length} models; no substitution was made.');
      }
    }, skip: _gateEnabled(metadataGate) ? null : _metadataSkipReason);
  });

  group('LIVE VERIFIED — Groq streaming chat (double opt-in)', () {
    test('one synthetic prompt through the real controller and adapter',
        () async {
      final AiProviderConfig config = await _resolveConfiguredGroq();
      final AiCredentialStore store = await _requireCredential(config);
      final Directory directory = _isolatedDirectory();
      addTearDown(() {
        if (directory.existsSync()) directory.deleteSync(recursive: true);
      });

      final AuraLogger logger = AuraLogger();
      ProfileAccess accessReader() => ProfileAccess(ProfileSession.initial);
      final AiConfigController configs = AiConfigController(
        profile: AuraProfile.family,
        store: AiConfigStore(directory: directory, profile: AuraProfile.family),
        logger: logger,
        accessReader: accessReader,
      );
      await configs.load();
      await configs.upsert(config);

      final AiPreferencesController preferences = AiPreferencesController(
        profile: AuraProfile.family,
        store: AiPreferencesStore(
          directory: directory,
          profile: AuraProfile.family,
        ),
        accessReader: accessReader,
      );
      await preferences.load();
      await preferences.selectProvider(config.id);
      // Consent is granted only inside this temporary fixture; the real
      // FAMILY preference file is never opened or written.
      await preferences.setConsent(true);

      final AiConversationLibraryController conversations =
          AiConversationLibraryController(
        profile: AuraProfile.family,
        storage: AiConversationStore(
          directory: directory,
          profile: AuraProfile.family,
        ),
        accessReader: accessReader,
      );
      await conversations.load();

      final _RecordingDiagnostics diagnostics = _RecordingDiagnostics();
      final AiClient client = OpenAiCompatibleAiClient(
        transport: const DartIoAiHttpTransport(),
        diagnostics: diagnostics,
      );
      final AiChatController chat = AiChatController(
        profile: AuraProfile.family,
        access: ProfileAccess(ProfileSession.initial),
        accessReader: accessReader,
        configs: configs,
        preferences: preferences,
        conversations: conversations,
        credentials: AiCredentialController(
          profile: AuraProfile.family,
          store: store,
          accessReader: accessReader,
        ),
        client: client,
        logger: logger,
        diagnostics: diagnostics,
        contextAssembler: const DefaultAiContextAssembler(),
      );
      addTearDown(chat.dispose);

      await chat.send(_syntheticPrompt).timeout(const Duration(seconds: 60));

      expect(chat.state.isBusy, isFalse);
      expect(chat.state.hasError, isFalse,
          reason: chat.state.errorMessage ?? '');
      expect(chat.state.streamingText, isNotNull);
      expect(chat.state.streamingText!.trim(), isNotEmpty);
      expect(conversations.state, hasLength(1));
      expect(
        conversations.state.single
            .list()
            .any((AiMessage message) => message.content == _syntheticPrompt),
        isTrue,
      );
      expect(diagnostics.serialized, isNot(contains(_syntheticPrompt)));
      expect(diagnostics.serialized, isNot(contains('Bearer')));
    },
        skip: _gateEnabled(metadataGate) && _gateEnabled(chatGate)
            ? null
            : _chatSkipReason);
  });
}
