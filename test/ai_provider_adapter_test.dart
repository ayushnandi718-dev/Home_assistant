import 'dart:async';
import 'dart:convert';

import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/openai_compatible_client.dart';
import 'package:aura_hub/features/ai/data/openai_sse_parser.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
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

AiProviderConfig _config({
  String baseUrl = 'https://api.groq.com/openai/v1/',
  bool local = false,
}) =>
    AiProviderConfig(
      id: 'groq-test',
      label: 'Groq test',
      kind:
          local ? AiProviderKind.localOllama : AiProviderKind.openAiCompatible,
      baseUrl: baseUrl,
      model: 'user-selected-model',
      enabled: true,
    );

String _sseChunk(String content) => 'data: ${jsonEncode(<String, dynamic>{
          'choices': <dynamic>[
            <String, dynamic>{
              'delta': <String, dynamic>{'content': content},
            },
          ],
        })}\n\n';

void main() {
  group('OpenAiCompatibleAiClient request construction', () {
    test('sends only the system policy and transcript with a transient key',
        () async {
      final FakeAiTransport transport = FakeAiTransport();
      transport.enqueue(
        AiHttpResponse(
          statusCode: 200,
          body: Stream<String>.value('data: [DONE]\n\n'),
        ),
      );
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);

      final List<String> chunks = await client
          .streamCompletion(
            config: _config(),
            messages: <AiMessage>[
              AiMessage(
                role: AiMessageRole.user,
                content: 'বাংলায় উত্তর দিন',
                timestamp: DateTime(2026),
              ),
            ],
            language: AiLanguage.bengali,
            context: const AiRequestContext(apiKey: 'FAKE-KEY'),
          )
          .toList();

      expect(chunks, isEmpty);
      final AiHttpRequest request = transport.lastRequest!;
      expect(request.method, AiHttpMethod.post);
      expect(request.uri.toString(),
          'https://api.groq.com/openai/v1/chat/completions');
      expect(request.headers['Authorization'], 'Bearer FAKE-KEY');
      expect(request.headers['Accept'], 'text/event-stream');

      final Map<String, dynamic> body =
          jsonDecode(request.body!) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      expect(body['model'], 'user-selected-model');
      expect(body.containsKey('tools'), isFalse);
      final List<dynamic> messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(2));
      expect(messages.first['role'], 'system');
      expect(messages.first['content'], contains('বাংলা'));
      expect(messages.first['content'], contains('code-switching'));
      expect(messages.last['content'], 'বাংলায় উত্তর দিন');
      expect(request.toString(), isNot(contains('FAKE-KEY')));
    });

    test('requires a key for remote endpoints but allows loopback adapters',
        () async {
      final FakeAiTransport transport = FakeAiTransport();
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);

      await expectLater(
        client.streamCompletion(
          config: _config(local: false),
          messages: const <AiMessage>[],
        ).toList(),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.missingCredentials,
          ),
        ),
      );

      transport.enqueue(
        AiHttpResponse(
          statusCode: 200,
          body: Stream<String>.value('data: [DONE]\n\n'),
        ),
      );
      await client.streamCompletion(
        config: _config(
          baseUrl: 'http://127.0.0.1:11434/v1',
          local: true,
        ),
        messages: const <AiMessage>[],
      ).toList();
      expect(
          transport.lastRequest!.headers.containsKey('Authorization'), isFalse);
    });
  });

  group('SSE parsing and errors', () {
    test('parses deltas, comments and DONE across chunk boundaries', () async {
      final Stream<String> source = Stream<String>.fromIterable(<String>[
        ': keep-alive\n\ndata: ${jsonEncode(<String, dynamic>{
              'choices': <dynamic>[
                <String, dynamic>{
                  'delta': <String, dynamic>{'content': 'Hello'},
                },
              ],
            })}\r\n\r\ndata: {"choices":[{"delta":{"content":" wo',
        'rld"}}]}\n\ndata: [DONE]\n\n',
      ]);

      expect(
          await parseOpenAiSse(source).toList(), <String>['Hello', ' world']);
    });

    test('malformed data is an error, never invented content', () async {
      await expectLater(
        parseOpenAiSse(
          Stream<String>.value('data: {broken}\n\n'),
        ).toList(),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.malformedResponse,
          ),
        ),
      );
    });

    test('maps provider HTTP errors without echoing response bodies', () async {
      final FakeAiTransport transport = FakeAiTransport();
      transport.enqueue(
        AiHttpResponse(
          statusCode: 429,
          body: Stream<String>.value('SECRET-BODY-SHOULD-NOT-LEAK'),
        ),
      );
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);

      await expectLater(
        client
            .streamCompletion(
              config: _config(),
              messages: const <AiMessage>[],
              context: const AiRequestContext(apiKey: 'FAKE-KEY'),
            )
            .toList(),
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
                isNot(contains('SECRET-BODY')),
              ),
        ),
      );
    });
  });

  group('Cancellation', () {
    test('cancels an active stream without fabricating a final delta',
        () async {
      final StreamController<String> body = StreamController<String>();
      final FakeAiTransport transport = FakeAiTransport();
      transport.enqueue(
        AiHttpResponse(statusCode: 200, body: body.stream),
      );
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);
      final AiCancelToken token = AiCancelToken();

      final Future<List<String>> received = client
          .streamCompletion(
            config: _config(),
            messages: const <AiMessage>[],
            context: AiRequestContext(apiKey: 'FAKE-KEY', cancelToken: token),
          )
          .toList();

      await Future<void>.delayed(Duration.zero);
      body.add(_sseChunk('partial'));
      await Future<void>.delayed(Duration.zero);
      token.cancel();
      await body.close();

      expect(await received, <String>['partial']);
      expect(transport.lastToken, same(token));
    });

    test('refuses a request that was cancelled before sending', () async {
      final FakeAiTransport transport = FakeAiTransport();
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);
      final AiCancelToken token = AiCancelToken()..cancel();

      await expectLater(
        client
            .streamCompletion(
              config: _config(),
              messages: const <AiMessage>[],
              context: AiRequestContext(apiKey: 'FAKE-KEY', cancelToken: token),
            )
            .toList(),
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
  });

  group('Connection test', () {
    test('makes a real metadata request and requires a valid model list',
        () async {
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

      expect(transport.lastRequest!.method, AiHttpMethod.get);
      expect(transport.lastRequest!.uri.toString(),
          'https://api.groq.com/openai/v1/models');
      expect(
          transport.lastRequest!.headers['Authorization'], 'Bearer FAKE-KEY');
    });

    test('a saved key alone never makes the test pass', () async {
      final FakeAiTransport transport = FakeAiTransport();
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);

      await expectLater(
        client.testConnection(config: _config()),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.missingCredentials,
          ),
        ),
      );
      expect(transport.lastRequest, isNull);
    });
  });
}
