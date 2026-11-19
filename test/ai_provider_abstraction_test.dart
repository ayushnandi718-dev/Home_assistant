import 'dart:async';
import 'dart:convert';

import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/default_ai_provider_registry.dart';
import 'package:aura_hub/features/ai/data/openai_compatible_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_router.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAiTransport implements AiHttpTransport {
  final List<AiHttpResponse> responses = <AiHttpResponse>[];
  AiHttpRequest? lastRequest;
  AiCancelToken? lastToken;

  void enqueue(AiHttpResponse response) => responses.add(response);

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    lastRequest = request;
    lastToken = cancelToken;
    if (responses.isEmpty) {
      throw const AiException(
        AiFailureKind.providerUnavailable,
        'No canned response was queued.',
      );
    }
    return responses.removeAt(0);
  }
}

class FakeProviderAdapter implements AiProviderAdapter {
  FakeProviderAdapter(this.supportedKinds, this.name);

  @override
  final Set<AiProviderKind> supportedKinds;
  final String name;

  int streamCalls = 0;
  int testCalls = 0;
  int modelCalls = 0;

  @override
  AiProviderCapabilities get capabilities => const AiProviderCapabilities(
        streaming: true,
        modelDiscovery: true,
        connectionTest: true,
      );

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.auto,
    AiRequestContext? context,
  }) {
    streamCalls++;
    return Stream<String>.value(name);
  }

  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    testCalls++;
  }

  @override
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {
    modelCalls++;
    return <AiModelInfo>[AiModelInfo(id: name, label: name)];
  }
}

AiProviderConfig _config({
  AiProviderKind kind = AiProviderKind.openAiCompatible,
  String baseUrl = 'https://api.groq.com/openai/v1',
}) =>
    AiProviderConfig(
      id: 'provider-${kind.name}',
      label: 'Test provider',
      kind: kind,
      baseUrl: baseUrl,
      model: 'user-selected-model',
      enabled: true,
    );

void main() {
  group('Provider abstraction', () {
    test('router selects adapters by provider kind', () async {
      final FakeProviderAdapter openAi = FakeProviderAdapter(
          <AiProviderKind>{AiProviderKind.openAiCompatible}, 'openai');
      final FakeProviderAdapter ollama = FakeProviderAdapter(
          <AiProviderKind>{AiProviderKind.localOllama}, 'ollama');
      final AiProviderRouter router = AiProviderRouter(
        registry:
            DefaultAiProviderRegistry(<AiProviderAdapter>[openAi, ollama]),
      );

      expect(
        await router.streamCompletion(
          config: _config(),
          messages: const <AiMessage>[],
        ).toList(),
        <String>['openai'],
      );
      await router.testConnection(
          config: _config(kind: AiProviderKind.localOllama));
      expect(
        await router.listModels(
            config: _config(kind: AiProviderKind.localOllama)),
        hasLength(1),
      );

      expect(openAi.streamCalls, 1);
      expect(openAi.testCalls, 0);
      expect(ollama.testCalls, 1);
      expect(ollama.modelCalls, 1);
      expect(router.descriptors, hasLength(2));
    });

    test('unsupported kinds fail closed without calling an adapter', () async {
      final FakeProviderAdapter adapter = FakeProviderAdapter(
          <AiProviderKind>{AiProviderKind.openAiCompatible}, 'openai');
      final AiProviderRouter router = AiProviderRouter(
        registry: DefaultAiProviderRegistry(<AiProviderAdapter>[adapter]),
      );
      final AiProviderConfig config =
          _config(kind: AiProviderKind.googleGemini);

      expect(
          () => router.streamCompletion(
                config: config,
                messages: const <AiMessage>[],
              ),
          throwsA(isA<AiException>()));
      await expectLater(
        router.testConnection(config: config),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.unsupportedProvider,
          ),
        ),
      );
      await expectLater(
        router.listModels(config: config),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.unsupportedProvider,
          ),
        ),
      );
      expect(adapter.streamCalls, 0);
      expect(adapter.testCalls, 0);
      expect(adapter.modelCalls, 0);
    });

    test('duplicate adapter claims are rejected at registration', () {
      expect(
        () => DefaultAiProviderRegistry(<AiProviderAdapter>[
          FakeProviderAdapter(
              <AiProviderKind>{AiProviderKind.openAiCompatible}, 'a'),
          FakeProviderAdapter(
              <AiProviderKind>{AiProviderKind.openAiCompatible}, 'b'),
        ]),
        throwsArgumentError,
      );
    });

    test('OpenAI-compatible adapter declares honest capabilities', () {
      final OpenAiCompatibleAiClient client = OpenAiCompatibleAiClient(
        transport: FakeAiTransport(),
      );
      expect(
        client.supportedKinds,
        <AiProviderKind>{
          AiProviderKind.openAiCompatible,
          AiProviderKind.localOllama,
        },
      );
      expect(client.capabilities.streaming, isTrue);
      expect(client.capabilities.modelDiscovery, isTrue);
      expect(client.capabilities.connectionTest, isTrue);
    });
  });

  group('OpenAI-compatible model discovery', () {
    test('parses bounded model metadata without sending conversation content',
        () async {
      final FakeAiTransport transport = FakeAiTransport();
      transport.enqueue(
        AiHttpResponse(
          statusCode: 200,
          body: Stream<String>.value(jsonEncode(<String, dynamic>{
            'data': <dynamic>[
              <String, dynamic>{
                'id': 'llama-3.3-70b-versatile',
                'name': 'Llama 3.3 70B',
                'owned_by': 'groq',
                'context_window': 131072,
                'secret': 'MUST-NOT-BE-RETAINED',
              },
            ],
          })),
        ),
      );
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);

      final List<AiModelInfo> models = await client.listModels(
        config: _config(),
        context: const AiRequestContext(apiKey: 'FAKE-KEY'),
      );

      expect(models, hasLength(1));
      expect(models.single.id, 'llama-3.3-70b-versatile');
      expect(models.single.label, 'Llama 3.3 70B');
      expect(models.single.ownedBy, 'groq');
      expect(models.single.contextWindow, 131072);
      expect(models.single.toString(), isNot(contains('MUST-NOT-BE-RETAINED')));
      expect(transport.lastRequest!.method, AiHttpMethod.get);
      expect(
        transport.lastRequest!.uri.toString(),
        'https://api.groq.com/openai/v1/models',
      );
      expect(transport.lastRequest!.body, isNull);
      expect(
        transport.lastRequest!.headers['Authorization'],
        'Bearer FAKE-KEY',
      );
    });

    test('rejects malformed model lists without inventing entries', () async {
      final List<String> invalidBodies = <String>[
        '{"data":"not-a-list"}',
        '{"data":[{}]}',
        '{"data":[{"id":""},{"id":"x"}]}',
        '{"data":[{"id":"x"},{"id":"x"}]}',
        '{"data":[${List<String>.filled(201, '{"id":"model"}').join(',')}]}',
      ];
      for (final String body in invalidBodies) {
        final FakeAiTransport transport = FakeAiTransport();
        transport.enqueue(
          AiHttpResponse(statusCode: 200, body: Stream<String>.value(body)),
        );
        final OpenAiCompatibleAiClient client =
            OpenAiCompatibleAiClient(transport: transport);
        await expectLater(
          client.listModels(
            config: _config(),
            context: const AiRequestContext(apiKey: 'FAKE-KEY'),
          ),
          throwsA(
            isA<AiException>().having(
              (AiException error) => error.kind,
              'kind',
              AiFailureKind.malformedResponse,
            ),
          ),
          reason: body,
        );
      }
    });

    test('cancellation blocks discovery before any request is sent', () async {
      final FakeAiTransport transport = FakeAiTransport();
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);
      final AiCancelToken token = AiCancelToken()..cancel();

      await expectLater(
        client.listModels(
          config: _config(),
          context: AiRequestContext(apiKey: 'FAKE-KEY', cancelToken: token),
        ),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.cancelled,
          ),
        ),
      );
      expect(transport.lastRequest, isNull);
    });

    test('HTTP failures use the shared safe error taxonomy', () async {
      final FakeAiTransport transport = FakeAiTransport();
      transport.enqueue(
        AiHttpResponse(
          statusCode: 429,
          body: Stream<String>.value('SECRET-RESPONSE-BODY'),
        ),
      );
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);

      await expectLater(
        client.listModels(
          config: _config(),
          context: const AiRequestContext(apiKey: 'FAKE-KEY'),
        ),
        throwsA(
          isA<AiException>()
              .having(
                (AiException error) => error.kind,
                'kind',
                AiFailureKind.rateLimited,
              )
              .having(
                (AiException error) => error.toString(),
                'message',
                isNot(contains('SECRET-RESPONSE-BODY')),
              ),
        ),
      );
    });

    test('connection test still accepts an empty model list', () async {
      final FakeAiTransport transport = FakeAiTransport();
      transport.enqueue(
        AiHttpResponse(
          statusCode: 200,
          body: Stream<String>.value('{"data":[]}'),
        ),
      );
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);

      await client.testConnection(
        config: _config(),
        context: const AiRequestContext(apiKey: 'FAKE-KEY'),
      );
      expect(transport.lastRequest!.uri.path.endsWith('/models'), isTrue);
    });
  });
}
