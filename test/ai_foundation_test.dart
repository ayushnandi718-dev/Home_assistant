import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:flutter_test/flutter_test.dart';

AiProviderConfig _config({
  String id = 'primary',
  String baseUrl = 'https://api.example.com/v1',
  bool enabled = false,
}) =>
    AiProviderConfig(
      id: id,
      label: 'Test provider',
      kind: AiProviderKind.openAiCompatible,
      baseUrl: baseUrl,
      model: 'test-model',
      enabled: enabled,
    );

void main() {
  group('AiLanguage', () {
    test('parses supported codes safely', () {
      expect(AiLanguage.tryParse('en'), AiLanguage.english);
      expect(AiLanguage.tryParse('HI'), AiLanguage.hindi);
      expect(AiLanguage.tryParse(' bn '), AiLanguage.bengali);
      expect(AiLanguage.tryParse('fr'), isNull);
      expect(AiLanguage.tryParse(null), isNull);
      expect(AiLanguage.tryParse(''), isNull);
    });

    test('falls back to English and exposes labels', () {
      expect(AiLanguage.fromCode('xx'), AiLanguage.english);
      expect(AiLanguage.fromCode(null), AiLanguage.english);
      expect(AiLanguage.english.code, 'en');
      expect(AiLanguage.hindi.code, 'hi');
      expect(AiLanguage.bengali.label, 'Bengali');
    });
  });

  group('AiProviderConfig', () {
    test('validation accepts https and loopback http only', () {
      expect(_config().validate(), isNull);
      expect(_config(baseUrl: 'https://api.example.com').validate(), isNull);
      expect(_config(baseUrl: 'http://127.0.0.1:11434').validate(), isNull);
      expect(_config(baseUrl: 'http://localhost:11434').validate(), isNull);
      expect(_config(baseUrl: 'http://api.example.com').validate(), isNotNull);
      expect(_config(baseUrl: 'not a url').validate(), isNotNull);
    });

    test('JSON round trip carries no secret fields', () {
      final Map<String, dynamic> json = _config(enabled: true).toJson();
      final Set<String> keys =
          json.keys.map((String key) => key.toLowerCase()).toSet();
      for (final String forbidden in <String>[
        'key',
        'token',
        'secret',
        'password',
        'credential',
      ]) {
        expect(keys.any((String key) => key.contains(forbidden)), isFalse);
      }
      expect(jsonEncode(json), isNot(contains('apiKey')));

      final AiProviderConfig restored = AiProviderConfig.fromJson(json);
      expect(restored.id, 'primary');
      expect(restored.kind, AiProviderKind.openAiCompatible);
      expect(restored.baseUrl, 'https://api.example.com/v1');
      expect(restored.enabled, isTrue);
      expect(restored.language, AiLanguage.english);
    });

    test('capabilities description is explicitly interface-only', () {
      expect(
        AiProviderConfig.capabilities,
        'streaming + structured tools (interface only)',
      );
    });
  });

  group('AiConversation', () {
    test('history is bounded by the runtime limit and keeps newest messages',
        () {
      AiConversation conversation = const AiConversation(id: 'c1');
      final int limit = AuraRuntimeConfig.maxConversationMessages;
      for (int index = 0; index < limit + 10; index++) {
        conversation = conversation.append(
          AiMessage(
            role: AiMessageRole.user,
            content: 'm$index',
            timestamp: DateTime.fromMillisecondsSinceEpoch(index),
          ),
        );
      }

      expect(conversation.length, limit);
      expect(conversation.list().first.content, 'm10');
      expect(conversation.list().last.content, 'm${limit + 9}');
      expect(conversation.clear().isEmpty, isTrue);
    });
  });

  group('NoAiClient', () {
    test('throws AiUnavailableException immediately', () {
      final AiClient client = const NoAiClient();
      expect(
        () => client.streamCompletion(
          config: _config(),
          messages: const <AiMessage>[],
        ),
        throwsA(isA<AiUnavailableException>()),
      );
    });
  });

  group('AiConfigStore', () {
    late Directory directory;
    late AiConfigStore store;
    late File file;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_ai_test_');
      store = AiConfigStore(directory: directory);
      file = File(
        '${directory.path}${Platform.pathSeparator}ai_providers.json',
      );
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('saves and loads configs without writing secrets', () async {
      await store.save(<AiProviderConfig>[
        _config(
          id: 'local',
          baseUrl: 'http://127.0.0.1:11434',
          enabled: true,
        ),
      ]);

      final List<AiProviderConfig> loaded = await store.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.id, 'local');
      expect(loaded.single.enabled, isTrue);

      final String raw = (await file.readAsString()).toLowerCase();
      expect(raw, isNot(contains('apikey')));
      expect(raw, isNot(contains('secret')));
    });

    test('corrupt file falls back to an empty list', () async {
      await file.writeAsString('{broken');
      expect(await store.load(), isEmpty);
    });

    test('upsert replaces an existing id', () async {
      await store.upsert(_config(id: 'a'));
      await store.upsert(
        _config(id: 'a', baseUrl: 'https://other.example.com', enabled: true),
      );

      final List<AiProviderConfig> loaded = await store.load();
      expect(loaded, hasLength(1));
      expect(loaded.single.enabled, isTrue);
    });
  });
}
