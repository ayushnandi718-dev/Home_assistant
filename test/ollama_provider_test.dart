import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/default_ai_provider_registry.dart';
import 'package:aura_hub/features/ai/data/ollama_ai_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_context.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_diagnostics.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_router.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:flutter_test/flutter_test.dart';

typedef _OllamaHandler = Future<void> Function(HttpRequest request);

/// In-process Ollama stand-in. No real Ollama installation is needed.
class _MockOllamaServer {
  _MockOllamaServer(this._server) {
    _server.listen((HttpRequest request) {
      _handle(request).catchError((Object error) async {
        // A cancelled client can close a socket mid-response. That is expected
        // and must not surface as an unhandled test-process error.
        try {
          await request.response.close();
        } on Object {
          // Ignore.
        }
      });
    });
  }

  final HttpServer _server;

  String? lastMethod;
  String? lastPath;
  String? lastBody;
  Map<String, String>? lastHeaders;
  _OllamaHandler? handler;

  int get port => _server.port;

  static Future<_MockOllamaServer> start() async {
    final HttpServer server =
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    return _MockOllamaServer(server);
  }

  Future<void> close() => _server.close();

  AiProviderConfig config({
    String model = 'llama3.2',
    String id = 'ollama-test',
  }) =>
      AiProviderConfig(
        id: id,
        label: 'Local Ollama test',
        kind: AiProviderKind.localOllama,
        baseUrl: 'http://127.0.0.1:$port',
        model: model,
        enabled: true,
      );

  Future<void> _handle(HttpRequest request) async {
    lastMethod = request.method;
    lastPath = request.uri.path;
    lastHeaders = <String, String>{
      'content-type': request.headers.value('content-type') ?? '',
      'accept': request.headers.value('accept') ?? '',
      'authorization': request.headers.value('authorization') ?? '',
    };
    lastBody = await utf8.decoder.bind(request).join();
    final _OllamaHandler? next = handler;
    if (next == null) {
      request.response.statusCode = 404;
      await request.response.close();
      return;
    }
    await next(request);
  }
}

class _RawRequest {
  const _RawRequest({
    required this.socket,
    required this.method,
    required this.path,
    required this.body,
  });

  final Socket socket;
  final String method;
  final String path;
  final String body;
}

/// Minimal raw HTTP/1.1 server for tests that must emit NDJSON frames before
/// the response is complete. `dart:io` HttpServer buffers too aggressively for
/// that, while raw sockets give deterministic chunk boundaries.
class _RawOllamaServer {
  _RawOllamaServer._(this._server) {
    _server.listen(_onConnection);
  }

  final ServerSocket _server;
  final StreamController<_RawRequest> _requests =
      StreamController<_RawRequest>.broadcast();

  int get port => _server.port;
  Stream<_RawRequest> get requests => _requests.stream;

  static Future<_RawOllamaServer> start() async {
    final ServerSocket server =
        await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    return _RawOllamaServer._(server);
  }

  AiProviderConfig config() => AiProviderConfig(
        id: 'ollama-raw',
        label: 'Raw Ollama test',
        kind: AiProviderKind.localOllama,
        baseUrl: 'http://127.0.0.1:$port',
        model: 'llama3.2',
        enabled: true,
      );

  Future<void> close() async {
    await _requests.close();
    await _server.close();
  }

  void _onConnection(Socket socket) {
    final List<int> buffer = <int>[];
    int? headerEnd;
    int? contentLength;
    String? headerText;

    socket.listen(
      (List<int> data) {
        buffer.addAll(data);
        if (headerEnd == null) {
          final int index = _indexOf(buffer, utf8.encode('\r\n\r\n'));
          if (index < 0) return;
          headerEnd = index + 4;
          headerText = utf8.decode(buffer.sublist(0, index));
          contentLength = _rawContentLength(headerText!);
        }
        if (buffer.length - headerEnd! < contentLength!) return;
        final List<String> requestLine =
            headerText!.split('\r\n').first.split(' ');
        final String body = utf8.decode(
          buffer.sublist(headerEnd!, headerEnd! + contentLength!),
        );
        _requests.add(
          _RawRequest(
            socket: socket,
            method: requestLine.first,
            path: requestLine.length > 1 ? requestLine[1] : '/',
            body: body,
          ),
        );
      },
      onError: (Object error) {},
    );
  }
}

int _indexOf(List<int> haystack, List<int> needle) {
  for (int i = 0; i <= haystack.length - needle.length; i++) {
    bool matches = true;
    for (int j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return i;
  }
  return -1;
}

int _rawContentLength(String headerText) {
  for (final String line in headerText.split('\r\n').skip(1)) {
    final int colon = line.indexOf(':');
    if (colon < 0) continue;
    if (line.substring(0, colon).trim().toLowerCase() == 'content-length') {
      return int.tryParse(line.substring(colon + 1).trim()) ?? 0;
    }
  }
  return 0;
}

Future<void> _writeRawHeaders(Socket socket) async {
  socket.write(
    'HTTP/1.1 200 OK\r\n'
    'Content-Type: application/x-ndjson\r\n'
    'Transfer-Encoding: chunked\r\n'
    'Connection: close\r\n'
    '\r\n',
  );
  await socket.flush();
}

Future<void> _writeRawChunk(Socket socket, String line) async {
  final List<int> bytes = utf8.encode(line);
  socket.write('${bytes.length.toRadixString(16)}\r\n');
  socket.add(bytes);
  socket.write('\r\n');
  await socket.flush();
}

Future<void> _finishRawStream(Socket socket) async {
  socket.write('0\r\n\r\n');
  await socket.flush();
}

class _DelayedTransport implements AiHttpTransport {
  final Completer<void> release = Completer<void>();
  bool sent = false;

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    sent = true;
    await release.future;
    return AiHttpResponse(
      statusCode: 200,
      body: Stream<String>.value(
        _ndjson(<String, dynamic>{'done': true}),
      ),
    );
  }
}

class _CancelTrackingTransport implements AiHttpTransport {
  final StreamController<String> body = StreamController<String>();
  bool sent = false;
  bool cancelled = false;

  _CancelTrackingTransport() {
    body.onCancel = () {
      cancelled = true;
    };
  }

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    sent = true;
    body.add(_ndjson(_streamChunk('partial')));
    return AiHttpResponse(statusCode: 200, body: body.stream);
  }
}

class _RecordingDiagnostics extends AiDiagnostics {
  final List<AiDiagnosticEvent> events = <AiDiagnosticEvent>[];

  @override
  void record(AiDiagnosticEvent event) => events.add(event);
}

OllamaAiAdapter _adapter({AiDiagnostics? diagnostics}) => OllamaAiAdapter(
      transport: const DartIoAiHttpTransport(),
      diagnostics: diagnostics ?? const NoAiDiagnostics(),
    );

String _ndjson(Object value) => '${jsonEncode(value)}\n';

Map<String, dynamic> _streamChunk(String content, {bool done = false}) =>
    <String, dynamic>{
      'message': <String, dynamic>{'role': 'assistant', 'content': content},
      'done': done,
    };

Future<void> _replyJson(
  HttpRequest request,
  Object value, {
  int statusCode = 200,
}) async {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType.json;
  request.response.write(jsonEncode(value));
  await request.response.close();
}

Future<void> _waitUntil(bool Function() condition) async {
  final DateTime deadline = DateTime.now().add(const Duration(seconds: 5));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for mock Ollama state.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('Ollama native server detection', () {
    test('reports an available loopback server using /api/version', () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) => _replyJson(
            request,
            <String, dynamic>{
              'version': '0.5.7',
              'extra_internal_field': 'MUST-NOT-BE-RETAINED',
            },
          );

      expect(
        await _adapter().isAvailable(config: server.config()),
        isTrue,
      );
      expect(server.lastMethod, 'GET');
      expect(server.lastPath, '/api/version');
    });

    test('reports an unreadable version response as unavailable', () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) =>
          _replyJson(request, <String, dynamic>{'unexpected': true});

      expect(await _adapter().isAvailable(config: server.config()), isFalse);
    });

    test('handles connection refusal without throwing raw errors', () async {
      final HttpServer probe =
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final int port = probe.port;
      await probe.close();
      final AiProviderConfig config = AiProviderConfig(
        id: 'ollama-refused',
        label: 'Refused Ollama',
        kind: AiProviderKind.localOllama,
        baseUrl: 'http://127.0.0.1:$port',
        model: 'llama3.2',
        enabled: true,
      );

      expect(await _adapter().isAvailable(config: config), isFalse);
      await expectLater(
        _adapter().listModels(config: config),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.networkFailure,
          ),
        ),
      );
    });

    test('rejects invalid and non-loopback endpoints without contacting them',
        () async {
      const OllamaAiAdapter adapter = OllamaAiAdapter(
        transport: DartIoAiHttpTransport(),
      );
      for (final String baseUrl in <String>[
        'not-a-url',
        'ftp://127.0.0.1:11434',
        'http://192.168.1.50:11434',
        'https://ollama.example.com',
        'http://user:pass@127.0.0.1:11434',
        'http://localhost:11434',
        'http://127.example.com:11434',
        'http://127.0.0.1.evil.example:11434',
        'http://[::ffff:127.0.0.1]:11434',
      ]) {
        final AiProviderConfig config = AiProviderConfig(
          id: 'ollama-invalid',
          label: 'Invalid Ollama',
          kind: AiProviderKind.localOllama,
          baseUrl: baseUrl,
          model: 'llama3.2',
          enabled: true,
        );

        expect(await adapter.isAvailable(config: config), isFalse,
            reason: baseUrl);
        await expectLater(
          adapter.listModels(config: config),
          throwsA(
            isA<AiException>().having(
              (AiException error) => error.kind,
              'kind',
              AiFailureKind.configuration,
            ),
          ),
          reason: baseUrl,
        );
      }
    });
  });

  group('Ollama native model discovery', () {
    test('parses bounded metadata from /api/tags', () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) => _replyJson(
            request,
            <String, dynamic>{
              'models': <dynamic>[
                <String, dynamic>{
                  'name': 'llama3.2:latest',
                  'model': 'llama3.2:latest',
                  'size': 2019393189,
                  'modified_at': '2026-01-02T03:04:05Z',
                  'digest': 'sha256:abc123',
                  'internal': 'MUST-NOT-BE-RETAINED',
                },
              ],
            },
          );

      final List<AiModelInfo> models =
          await _adapter().listModels(config: server.config(model: ''));

      expect(models, hasLength(1));
      expect(models.single.id, 'llama3.2:latest');
      expect(models.single.label, 'llama3.2:latest');
      expect(models.single.identifier, 'llama3.2:latest');
      expect(models.single.sizeBytes, 2019393189);
      expect(models.single.modifiedAt, DateTime.parse('2026-01-02T03:04:05Z'));
      expect(models.single.digest, 'sha256:abc123');
      expect(
        models.single.toString(),
        isNot(contains('MUST-NOT-BE-RETAINED')),
      );
      expect(server.lastPath, '/api/tags');
      expect(server.lastMethod, 'GET');
      expect(server.lastBody, isEmpty);
    });

    test('returns an accurate empty state when no models are installed',
        () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) =>
          _replyJson(request, <String, dynamic>{'models': <dynamic>[]});

      expect(
        await _adapter().listModels(config: server.config(model: '')),
        isEmpty,
      );
    });

    test('rejects malformed or unbounded metadata without inventing models',
        () async {
      final List<Object> invalidBodies = <Object>[
        <String, dynamic>{'models': 'not-a-list'},
        <String, dynamic>{
          'models': List<dynamic>.filled(
            201,
            <String, dynamic>{
              'name': 'm',
              'model': 'm',
            },
          ),
        },
        <String, dynamic>{
          'models': <dynamic>[
            <String, dynamic>{'model': 'm'}
          ],
        },
        <String, dynamic>{
          'models': <dynamic>[
            <String, dynamic>{'name': ''}
          ],
        },
        <String, dynamic>{
          'models': <dynamic>[
            <String, dynamic>{'name': 'a', 'model': 'x' * 201},
          ],
        },
        <String, dynamic>{
          'models': <dynamic>[
            <String, dynamic>{'name': 'a', 'model': 'a', 'size': -1},
          ],
        },
        <String, dynamic>{
          'models': <dynamic>[
            <String, dynamic>{
              'name': 'a',
              'model': 'a',
              'modified_at': 'not-a-timestamp',
            },
          ],
        },
        <String, dynamic>{
          'models': <dynamic>[
            <String, dynamic>{'name': 'a', 'model': 'same'},
            <String, dynamic>{'name': 'b', 'model': 'same'},
          ],
        },
        'not-an-object',
      ];

      for (final Object body in invalidBodies) {
        final _MockOllamaServer server = await _MockOllamaServer.start();
        addTearDown(server.close);
        server.handler = (HttpRequest request) => _replyJson(request, body);

        await expectLater(
          _adapter().listModels(config: server.config(model: '')),
          throwsA(
            isA<AiException>().having(
              (AiException error) => error.kind,
              'kind',
              AiFailureKind.malformedResponse,
            ),
          ),
        );
        await server.close();
      }
    });
  });

  group('Ollama native chat streaming', () {
    test('posts a native /api/chat request with safe bounded instructions',
        () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) => _replyNdjson(request, <String>[
            _ndjson(_streamChunk('ok')),
            _ndjson(<String, dynamic>{'done': true}),
          ]);

      final List<String> chunks = await _adapter()
          .streamCompletion(
            config: server.config(),
            messages: <AiMessage>[
              AiMessage(
                role: AiMessageRole.system,
                content: 'SYSTEM-TRANSCRIPT-MUST-NOT-DUPLICATE',
                timestamp: DateTime(2026),
              ),
              AiMessage(
                role: AiMessageRole.user,
                content: 'বাংলায় উত্তর দিন',
                timestamp: DateTime(2026),
              ),
              AiMessage(
                role: AiMessageRole.assistant,
                content: 'previous answer',
                timestamp: DateTime(2026),
              ),
              AiMessage(
                role: AiMessageRole.user,
                content: 'another question',
                timestamp: DateTime(2026),
              ),
            ],
            language: AiLanguage.bengali,
            context: AiRequestContext(
              apiKey: 'SECRET-KEY-MUST-NOT-BE-SENT',
              assembledContext: AiAssembledContext(
                messages: const <AiMessage>[],
                systemInstructions: const <String>[
                  'Profile-scoped instruction'
                ],
                includedSources: const <AiContextSource>{},
                unavailableSources: const <AiContextSource>{},
                estimatedTokens: 1,
                budgetTokens: 100,
              ),
            ),
          )
          .toList();

      expect(chunks, <String>['ok']);
      expect(server.lastMethod, 'POST');
      expect(server.lastPath, '/api/chat');
      expect(server.lastHeaders!['content-type'], contains('application/json'));
      expect(server.lastHeaders!['accept'], 'application/x-ndjson');
      expect(server.lastHeaders!['authorization'], isEmpty);
      expect(server.lastBody, isNot(contains('SECRET-KEY-MUST-NOT-BE-SENT')));
      expect(server.lastBody,
          isNot(contains('SYSTEM-TRANSCRIPT-MUST-NOT-DUPLICATE')));

      final Map<String, dynamic> body =
          jsonDecode(server.lastBody!) as Map<String, dynamic>;
      expect(body['stream'], isTrue);
      expect(body['model'], 'llama3.2');
      expect(body.containsKey('tools'), isFalse);
      final List<dynamic> messages = body['messages'] as List<dynamic>;
      expect(messages, hasLength(5));
      expect(messages[0]['role'], 'system');
      expect(messages[0]['content'], contains('বাংলা'));
      expect(messages[1]['role'], 'system');
      expect(messages[1]['content'], 'Profile-scoped instruction');
      expect(
        messages.skip(2).map((dynamic item) => item['role'] as String).toList(),
        <String>['user', 'assistant', 'user'],
      );
    });

    test(
        'streams incremental deltas across chunk boundaries without duplicates',
        () async {
      final _RawOllamaServer server = await _RawOllamaServer.start();
      addTearDown(server.close);
      final Future<_RawRequest> incoming = server.requests.first;

      final Future<void> serving = () async {
        final _RawRequest request = await incoming;
        expect(request.method, 'POST');
        expect(request.path, '/api/chat');
        await _writeRawHeaders(request.socket);
        await _writeRawChunk(request.socket, _ndjson(_streamChunk('নমস্কার ')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await _writeRawChunk(
            request.socket, _ndjson(_streamChunk('**bold**\n')));
        await _writeRawChunk(request.socket, _ndjson(_streamChunk('शुभ दिन')));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await _writeRawChunk(
            request.socket, _ndjson(<String, dynamic>{'done': true}));
        await _finishRawStream(request.socket);
      }();

      final List<String> chunks = await _adapter()
          .streamCompletion(
            config: server.config(),
            messages: <AiMessage>[
              AiMessage(
                role: AiMessageRole.user,
                content: 'হিন্দিতে উত্তর দিন',
                timestamp: DateTime(2026),
              ),
            ],
            language: AiLanguage.auto,
          )
          .toList();
      await serving;

      expect(
        chunks,
        <String>['নমস্কার ', '**bold**\n', 'शुभ दिन'],
      );
      expect(chunks.join(), contains('**bold**'));
    });

    test('cancels an active stream without fabricating a final delta',
        () async {
      final _RawOllamaServer server = await _RawOllamaServer.start();
      addTearDown(server.close);
      final Future<_RawRequest> incoming = server.requests.first;
      final AiCancelToken token = AiCancelToken();
      final List<String> received = <String>[];

      final Future<void> consuming = () async {
        await for (final String chunk in _adapter().streamCompletion(
          config: server.config(),
          messages: const <AiMessage>[],
          context: AiRequestContext(cancelToken: token),
        )) {
          received.add(chunk);
        }
      }();
      final _RawRequest request = await incoming;
      await _writeRawHeaders(request.socket);
      await _writeRawChunk(request.socket, _ndjson(_streamChunk('partial')));

      await _waitUntil(() => received.contains('partial'));
      token.cancel();
      // The peer is intentionally left open: cancellation must stop the
      // subscription without waiting for another server chunk.
      await consuming;
      await request.socket.close();

      expect(received, <String>['partial']);
    });

    test('cancels the active transport subscription on token cancellation',
        () async {
      final _CancelTrackingTransport transport = _CancelTrackingTransport();
      final OllamaAiAdapter adapter = OllamaAiAdapter(transport: transport);
      final AiCancelToken token = AiCancelToken();
      final List<String> received = <String>[];
      const AiProviderConfig config = AiProviderConfig(
        id: 'ollama-cancel-subscription',
        label: 'Subscription cancel test',
        kind: AiProviderKind.localOllama,
        baseUrl: OllamaAiAdapter.defaultBaseUrl,
        model: 'llama3.2',
        enabled: true,
      );

      final Future<void> consuming = () async {
        await for (final String chunk in adapter.streamCompletion(
          config: config,
          messages: const <AiMessage>[],
          context: AiRequestContext(cancelToken: token),
        )) {
          received.add(chunk);
        }
      }();
      await _waitUntil(() => transport.sent && received.isNotEmpty);
      token.cancel();
      await consuming;

      expect(transport.cancelled, isTrue);
      expect(received, <String>['partial']);
    });

    test('cancels while the transport is still connecting', () async {
      final _DelayedTransport transport = _DelayedTransport();
      final OllamaAiAdapter adapter = OllamaAiAdapter(transport: transport);
      final AiCancelToken token = AiCancelToken();
      final AiProviderConfig config = AiProviderConfig(
        id: 'ollama-connect-cancel',
        label: 'Connection cancel test',
        kind: AiProviderKind.localOllama,
        baseUrl: OllamaAiAdapter.defaultBaseUrl,
        model: 'llama3.2',
        enabled: true,
      );

      final Future<List<String>> stream = adapter
          .streamCompletion(
            config: config,
            messages: const <AiMessage>[],
            context: AiRequestContext(cancelToken: token),
          )
          .toList();
      await _waitUntil(() => transport.sent);
      token.cancel();
      transport.release.complete();

      expect(await stream, isEmpty);
    });

    test('maps a stalled server body to a streaming timeout', () async {
      final _RawOllamaServer server = await _RawOllamaServer.start();
      addTearDown(server.close);
      final Future<_RawRequest> incoming = server.requests.first;
      final Future<List<String>> stream = _adapter()
          .streamCompletion(
            config: server.config(),
            messages: const <AiMessage>[],
            context: const AiRequestContext(
              timeout: Duration(milliseconds: 150),
            ),
          )
          .toList();
      final _RawRequest request = await incoming;
      await _writeRawHeaders(request.socket);
      await _writeRawChunk(request.socket, _ndjson(_streamChunk('partial')));

      try {
        await stream;
        fail('Expected a streaming timeout.');
      } on AiException catch (error) {
        expect(error.kind, AiFailureKind.streamingTimeout);
        expect(error.stage, AiRequestStage.stream);
      } finally {
        try {
          await _finishRawStream(request.socket);
        } on Object {
          // The timed-out transport may already have closed the socket.
        }
      }
    });

    test('rejects malformed NDJSON with a safe classified failure', () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) => _replyNdjson(request, <String>[
            '{broken-json}\n',
          ]);

      await expectLater(
        _adapter().streamCompletion(
          config: server.config(),
          messages: const <AiMessage>[],
        ).toList(),
        throwsA(
          isA<AiException>()
              .having(
                (AiException error) => error.kind,
                'kind',
                AiFailureKind.malformedResponse,
              )
              .having(
                (AiException error) => error.toString(),
                'message',
                isNot(contains('broken-json')),
              ),
        ),
      );
    });

    test('rejects an incomplete stream instead of inventing completion',
        () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) => _replyNdjson(request, <String>[
            _ndjson(_streamChunk('partial')),
          ]);

      await expectLater(
        _adapter().streamCompletion(
          config: server.config(),
          messages: const <AiMessage>[],
        ).toList(),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.streamInterrupted,
          ),
        ),
      );
    });

    test('treats done as terminal and discards data after it', () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) => _replyNdjson(request, <String>[
            _ndjson(_streamChunk('first')),
            _ndjson(<String, dynamic>{'done': true}),
            _ndjson(_streamChunk('AFTER-DONE-MUST-NOT-APPEAR')),
            _ndjson(<String, dynamic>{'done': true}),
          ]);

      expect(
        await _adapter().streamCompletion(
          config: server.config(),
          messages: const <AiMessage>[],
        ).toList(),
        <String>['first'],
      );
    });

    test('maps provider-side stream errors without echoing server text',
        () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) => _replyNdjson(request, <String>[
            _ndjson(<String, dynamic>{
              'error': 'SECRET-PROVIDER-ERROR-BODY',
              'done': true,
            }),
          ]);

      await expectLater(
        _adapter().streamCompletion(
          config: server.config(),
          messages: const <AiMessage>[],
        ).toList(),
        throwsA(
          isA<AiException>()
              .having(
                (AiException error) => error.kind,
                'kind',
                AiFailureKind.serverError,
              )
              .having(
                (AiException error) => error.toString(),
                'message',
                isNot(contains('SECRET-PROVIDER-ERROR-BODY')),
              ),
        ),
      );
    });

    test('diagnostics and exceptions never expose prompts or credentials',
        () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      final _RecordingDiagnostics diagnostics = _RecordingDiagnostics();
      server.handler = (HttpRequest request) => _replyNdjson(request, <String>[
            _ndjson(<String, dynamic>{
              'error': 'ECHO-OF-SECRET-PROMPT',
              'done': true,
            }),
          ]);

      try {
        await _adapter(diagnostics: diagnostics)
            .streamCompletion(
              config: server.config(),
              messages: <AiMessage>[
                AiMessage(
                  role: AiMessageRole.user,
                  content: 'SECRET-PROMPT',
                  timestamp: DateTime(2026),
                ),
              ],
              context: const AiRequestContext(apiKey: 'SECRET-KEY'),
            )
            .toList();
        fail('Expected a provider-side error.');
      } on AiException catch (error) {
        expect(error.toString(), isNot(contains('SECRET-PROMPT')));
        expect(error.toString(), isNot(contains('SECRET-KEY')));
        expect(error.toString(), isNot(contains('ECHO-OF-SECRET-PROMPT')));
      }

      expect(diagnostics.events, isNotEmpty);
      for (final AiDiagnosticEvent event in diagnostics.events) {
        final String context = event.context.toString();
        expect(context, isNot(contains('SECRET-PROMPT')));
        expect(context, isNot(contains('SECRET-KEY')));
        expect(context, isNot(contains('ECHO-OF-SECRET-PROMPT')));
        expect(event.host, '127.0.0.1');
      }
    });

    test('request-scoped context keeps profile markers isolated', () async {
      final _MockOllamaServer server = await _MockOllamaServer.start();
      addTearDown(server.close);
      server.handler = (HttpRequest request) => _replyNdjson(request, <String>[
            _ndjson(_streamChunk('ok')),
            _ndjson(<String, dynamic>{'done': true}),
          ]);
      final OllamaAiAdapter adapter = _adapter();

      final List<List<String>> bodies = <List<String>>[];
      for (final String marker in <String>['AYUSH-ONLY', 'FAMILY-ONLY']) {
        await adapter
            .streamCompletion(
              config: server.config(id: 'ollama-$marker'),
              messages: <AiMessage>[
                AiMessage(
                  role: AiMessageRole.user,
                  content: marker,
                  timestamp: DateTime(2026),
                ),
              ],
              context: AiRequestContext(apiKey: 'KEY-$marker'),
            )
            .toList();
        bodies.add(<String>[server.lastBody!, jsonEncode(server.lastHeaders)]);
      }

      expect(bodies[0][0], contains('AYUSH-ONLY'));
      expect(bodies[0][0], isNot(contains('FAMILY-ONLY')));
      expect(bodies[1][0], contains('FAMILY-ONLY'));
      expect(bodies[1][0], isNot(contains('AYUSH-ONLY')));
      for (final List<String> body in bodies) {
        expect(body.join(), isNot(contains('KEY-AYUSH-ONLY')));
        expect(body.join(), isNot(contains('KEY-FAMILY-ONLY')));
      }
    });
  });

  group('Ollama registry integration and fail-closed routing', () {
    test('unsupported provider kinds never reach the Ollama adapter', () async {
      final OllamaAiAdapter adapter = _adapter();
      final DefaultAiProviderRegistry registry =
          DefaultAiProviderRegistry(<AiProviderAdapter>[adapter]);
      final AiProviderRouter router = AiProviderRouter(registry: registry);
      final AiProviderConfig config = AiProviderConfig(
        id: 'future-provider',
        label: 'Unconfigured provider',
        kind: AiProviderKind.googleGemini,
        baseUrl: 'https://generativelanguage.googleapis.com',
        model: 'future-model',
        enabled: true,
      );

      expect(registry.supports(config), isFalse);
      expect(
        () => router.streamCompletion(
            config: config, messages: const <AiMessage>[]).toList(),
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
    });

    test('the native adapter refuses non-Ollama provider configs', () async {
      const OllamaAiAdapter adapter = OllamaAiAdapter(
        transport: DartIoAiHttpTransport(),
      );
      final AiProviderConfig config = AiProviderConfig(
        id: 'groq-test',
        label: 'Groq regression',
        kind: AiProviderKind.openAiCompatible,
        baseUrl: 'https://api.groq.com/openai/v1',
        model: 'llama-3.3-70b-versatile',
        enabled: true,
      );

      await expectLater(
        adapter.listModels(config: config),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.kind,
            'kind',
            AiFailureKind.unsupportedProvider,
          ),
        ),
      );
    });
  });
}

/// Kept separate so each test writes a complete NDJSON frame.
Future<void> _replyNdjson(
  HttpRequest request,
  List<String> lines, {
  int statusCode = 200,
}) async {
  request.response.statusCode = statusCode;
  request.response.headers.contentType = ContentType('application', 'x-ndjson');
  for (final String line in lines) {
    request.response.write(line.endsWith('\n') ? line : '$line\n');
  }
  await request.response.close();
}
