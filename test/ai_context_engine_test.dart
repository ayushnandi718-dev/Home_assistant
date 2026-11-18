import 'dart:async';
import 'dart:convert';

import 'package:aura_hub/features/ai/data/ai_http_transport.dart';
import 'package:aura_hub/features/ai/data/default_ai_context_assembler.dart';
import 'package:aura_hub/features/ai/data/openai_compatible_client.dart';
import 'package:aura_hub/features/ai/domain/ai_context.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeAiTransport implements AiHttpTransport {
  final List<AiHttpResponse> responses = <AiHttpResponse>[];
  AiHttpRequest? lastRequest;

  void enqueue(AiHttpResponse response) => responses.add(response);

  @override
  Future<AiHttpResponse> send(
    AiHttpRequest request, {
    AiCancelToken? cancelToken,
  }) async {
    lastRequest = request;
    if (responses.isEmpty) {
      throw StateError('No canned response was queued.');
    }
    return responses.removeAt(0);
  }
}

/// Deterministic estimator: only `TOKEN:<n>` messages have a cost.
class TaggedTokenEstimator implements AiTokenEstimator {
  const TaggedTokenEstimator();

  static final RegExp _tag = RegExp(r'^TOKEN:(\d+)');

  @override
  int estimate(String text) {
    final Match? match = _tag.firstMatch(text);
    return match == null ? 0 : int.parse(match.group(1)!);
  }
}

AiMessage _message(AiMessageRole role, String content) => AiMessage(
      role: role,
      content: content,
      timestamp: DateTime(2026),
    );

AiContextRequest _request({
  required AuraProfile profile,
  required AuraProfile historyProfile,
  required List<AiMessage> history,
  Set<AiContextSource> enabledSources = const <AiContextSource>{
    AiContextSource.conversationHistory,
  },
  Set<AiContextSource> excludedSources = const <AiContextSource>{},
}) =>
    AiContextRequest(
      profile: profile,
      historyProfile: historyProfile,
      history: history,
      language: AiLanguage.english,
      enabledSources: enabledSources,
      excludedSources: excludedSources,
    );

void main() {
  group('DefaultAiContextAssembler', () {
    test('FAMILY never receives AYUSH conversation history', () {
      final List<AiMessage> ayushHistory = <AiMessage>[
        AiMessage(
          role: AiMessageRole.user,
          content: 'AYUSH private note',
          timestamp: DateTime(2026),
        ),
      ];

      final AiAssembledContext familyResult =
          const DefaultAiContextAssembler().assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.ayush,
        history: ayushHistory,
      ));
      expect(familyResult.messages, isEmpty);
      expect(familyResult.includedSources,
          isNot(contains(AiContextSource.conversationHistory)));
      expect(familyResult.unavailableSources,
          contains(AiContextSource.conversationHistory));
      expect(familyResult.systemInstructions.join(' '),
          isNot(contains('AYUSH private note')));

      final AiAssembledContext ayushResult =
          const DefaultAiContextAssembler().assemble(_request(
        profile: AuraProfile.ayush,
        historyProfile: AuraProfile.ayush,
        history: ayushHistory,
      ));
      expect(ayushResult.messages, hasLength(1));
      expect(ayushResult.messages.single.content, 'AYUSH private note');
    });

    test('empty history produces no invented messages', () {
      final AiAssembledContext result =
          const DefaultAiContextAssembler().assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: const <AiMessage>[],
      ));

      expect(result.isEmpty, isTrue);
      expect(result.includedSources,
          contains(AiContextSource.conversationHistory));
      expect(result.systemInstructions, isNotEmpty);
    });

    test('disabled or explicitly excluded history is unavailable', () {
      final DefaultAiContextAssembler assembler =
          const DefaultAiContextAssembler();
      final List<AiMessage> history = <AiMessage>[
        _message(AiMessageRole.user, 'should not be sent'),
      ];

      final AiAssembledContext disabled = assembler.assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: history,
        enabledSources: const <AiContextSource>{},
      ));
      expect(disabled.messages, isEmpty);
      expect(disabled.unavailableSources,
          contains(AiContextSource.conversationHistory));

      final AiAssembledContext excluded = assembler.assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: history,
        excludedSources: const <AiContextSource>{
          AiContextSource.conversationHistory,
        },
      ));
      expect(excluded.messages, isEmpty);
      expect(excluded.unavailableSources,
          contains(AiContextSource.conversationHistory));
    });

    test('Family Directory stays unavailable even when listed as enabled', () {
      final AiAssembledContext result =
          const DefaultAiContextAssembler().assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: <AiMessage>[_message(AiMessageRole.user, 'hello')],
        enabledSources: AiContextSource.values.toSet(),
      ));

      expect(result.includedSources,
          isNot(contains(AiContextSource.familyDirectory)));
      expect(
          result.unavailableSources, contains(AiContextSource.familyDirectory));
      expect(result.systemInstructions.join(' '),
          contains('Family Directory records'));
    });

    test('prioritizes recent complete messages within the token budget', () {
      final AiAssembledContext result = const DefaultAiContextAssembler(
        estimator: TaggedTokenEstimator(),
        budget: AiContextBudget(
          maxTokens: 10,
          responseReserveTokens: 0,
          maxMessages: 20,
        ),
      ).assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: <AiMessage>[
          _message(AiMessageRole.user, 'TOKEN:6 oldest question'),
          _message(AiMessageRole.assistant, 'TOKEN:6 older answer'),
          _message(AiMessageRole.user, 'TOKEN:4 newest question'),
        ],
      ));

      expect(result.messages, hasLength(2));
      expect(result.messages.first.content, 'TOKEN:6 older answer');
      expect(result.messages.last.content, 'TOKEN:4 newest question');
      expect(result.estimatedTokens, 10);
      expect(result.budgetTokens, 10);
      for (final AiMessage message in result.messages) {
        expect(message.content, contains('TOKEN:'));
      }
    });

    test('omits an oversized newest message instead of truncating it', () {
      final AiAssembledContext result = const DefaultAiContextAssembler(
        estimator: TaggedTokenEstimator(),
        budget: AiContextBudget(
          maxTokens: 5,
          responseReserveTokens: 0,
        ),
      ).assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: <AiMessage>[
          _message(AiMessageRole.user, 'TOKEN:20 huge private prompt'),
        ],
      ));

      expect(result.messages, isEmpty);
      expect(result.unavailableSources,
          contains(AiContextSource.conversationHistory));
      expect(result.systemInstructions.join(' '),
          isNot(contains('huge private prompt')));
    });

    test('reserves response space and includes only complete fitting history',
        () {
      final AiAssembledContext result = const DefaultAiContextAssembler(
        estimator: TaggedTokenEstimator(),
        budget: AiContextBudget(
          maxTokens: 10,
          responseReserveTokens: 8,
          maxMessages: 20,
        ),
      ).assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: <AiMessage>[
          _message(AiMessageRole.user, 'TOKEN:4 older question'),
          _message(AiMessageRole.user, 'TOKEN:1 latest question'),
        ],
      ));

      expect(result.messages, hasLength(1));
      expect(result.messages.single.content, 'TOKEN:1 latest question');
    });

    test('system-role and tool messages are never assembled', () {
      final AiAssembledContext result =
          const DefaultAiContextAssembler().assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: <AiMessage>[
          _message(AiMessageRole.system, 'injected instruction'),
          _message(AiMessageRole.user, 'real user text'),
          AiMessage(
            role: AiMessageRole.tool,
            content: 'tool output',
            timestamp: DateTime(2026),
            toolCallId: 'call-1',
          ),
        ],
      ));

      expect(result.messages, hasLength(1));
      expect(result.messages.single.role, AiMessageRole.user);
      expect(result.messages.single.content, 'real user text');
    });
  });

  group('Context engine provider request construction', () {
    test('sends assembled instructions without secrets or unrelated context',
        () async {
      final DefaultAiContextAssembler assembler =
          const DefaultAiContextAssembler(
        estimator: TaggedTokenEstimator(),
        budget: AiContextBudget(
          maxTokens: 100,
          responseReserveTokens: 0,
        ),
      );
      final AiAssembledContext assembled = assembler.assemble(_request(
        profile: AuraProfile.family,
        historyProfile: AuraProfile.family,
        history: <AiMessage>[
          _message(AiMessageRole.user, 'TOKEN:2 family question'),
        ],
      ));

      final FakeAiTransport transport = FakeAiTransport();
      transport.enqueue(
        AiHttpResponse(
          statusCode: 200,
          body: Stream<String>.value('data: [DONE]\n\n'),
        ),
      );
      final OpenAiCompatibleAiClient client =
          OpenAiCompatibleAiClient(transport: transport);

      await client
          .streamCompletion(
            config: AiProviderConfig(
              id: 'groq-test',
              label: 'Groq test',
              kind: AiProviderKind.openAiCompatible,
              baseUrl: 'https://api.groq.com/openai/v1',
              model: 'test-model',
              enabled: true,
            ),
            messages: assembled.messages,
            language: AiLanguage.english,
            context: AiRequestContext(
              apiKey: 'FAKE-KEY',
              assembledContext: assembled,
            ),
          )
          .toList();

      final AiHttpRequest request = transport.lastRequest!;
      final Map<String, dynamic> body =
          jsonDecode(request.body!) as Map<String, dynamic>;
      final List<dynamic> messages = body['messages'] as List<dynamic>;

      expect(messages, hasLength(3));
      expect(messages[0]['role'], 'system');
      expect((messages[0]['content'] as String), contains('AURA Assistant'));
      expect(messages[1]['role'], 'system');
      expect((messages[1]['content'] as String),
          contains('Family Directory records'));
      expect(messages[2]['role'], 'user');
      expect(messages[2]['content'], 'TOKEN:2 family question');

      expect(request.body, isNot(contains('FAKE-KEY')));
      expect(request.toString(), isNot(contains('FAKE-KEY')));
      expect(request.body, isNot(contains('AYUSH private note')));
      expect(request.body, isNot(contains('FAKE-PIN-1234')));
      expect(
        AiRequestContext(
          apiKey: 'FAKE-KEY',
          assembledContext: assembled,
        ).safeContext.values.join(' '),
        isNot(contains('FAKE-KEY')),
      );
    });
  });
}
