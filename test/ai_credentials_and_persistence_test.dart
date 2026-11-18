import 'dart:io';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/data/ai_preferences_store.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVault implements CredentialVault {
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

Directory _tempDir() => Directory.systemTemp.createTempSync('aura_ai_persist_');

AiProviderConfig _config(String id) => AiProviderConfig(
      id: id,
      label: 'Provider $id',
      kind: AiProviderKind.openAiCompatible,
      baseUrl: 'https://api.example.com/v1',
      model: 'model-$id',
    );

void main() {
  group('AiCredentialStore', () {
    late FakeVault vault;
    late AiCredentialStore store;

    setUp(() {
      vault = FakeVault();
      store = AiCredentialStore(vault: vault);
    });

    test('stores, replaces and removes secrets without exposing them',
        () async {
      expect(
        await store.has(profileScope: 'family', providerId: 'groq'),
        isFalse,
      );

      final String handle = await store.save(
        profileScope: 'family',
        providerId: 'groq',
        apiKey: 'FAKE-KEY-ONE',
      );
      expect(handle, 'AURA_HUB/AI/family/groq');
      expect(handle, isNot(contains('FAKE-KEY-ONE')));
      expect(
        await store.readSecret(profileScope: 'family', providerId: 'groq'),
        'FAKE-KEY-ONE',
      );

      await store.save(
        profileScope: 'family',
        providerId: 'groq',
        apiKey: 'FAKE-KEY-TWO',
      );
      expect(
        await store.readSecret(profileScope: 'family', providerId: 'groq'),
        'FAKE-KEY-TWO',
      );

      await store.delete(profileScope: 'family', providerId: 'groq');
      expect(
        await store.has(profileScope: 'family', providerId: 'groq'),
        isFalse,
      );
      expect(
        await store.readSecret(profileScope: 'family', providerId: 'groq'),
        isNull,
      );
    });

    test('AYUSH and FAMILY keys never share a credential target', () async {
      await store.save(
        profileScope: 'family',
        providerId: 'groq',
        apiKey: 'FAMILY-KEY',
      );
      await store.save(
        profileScope: 'ayush',
        providerId: 'groq',
        apiKey: 'PRIVATE-KEY',
      );

      expect(
        await store.readSecret(profileScope: 'family', providerId: 'groq'),
        'FAMILY-KEY',
      );
      expect(
        await store.readSecret(profileScope: 'ayush', providerId: 'groq'),
        'PRIVATE-KEY',
      );
      expect(vault.secrets.length, 2);
    });

    test('empty keys are rejected before reaching the vault', () async {
      expect(
        () => store.save(
          profileScope: 'family',
          providerId: 'groq',
          apiKey: '   ',
        ),
        throwsArgumentError,
      );
      expect(vault.secrets, isEmpty);
    });
  });

  group('Profile-scoped AI persistence', () {
    late Directory directory;

    setUp(() {
      directory = _tempDir();
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('configs use separate files for AYUSH and FAMILY', () async {
      final AiConfigStore family =
          AiConfigStore(directory: directory, profile: AuraProfile.family);
      final AiConfigStore ayush =
          AiConfigStore(directory: directory, profile: AuraProfile.ayush);
      await family.upsert(_config('family-provider'));
      await ayush.upsert(_config('private-provider'));

      expect(await family.load(), hasLength(1));
      expect(await ayush.load(), hasLength(1));
      expect(
        (await family.load()).single.id,
        isNot((await ayush.load()).single.id),
      );
      expect(
        File('${directory.path}${Platform.pathSeparator}ai_providers_family.json')
            .existsSync(),
        isTrue,
      );
      expect(
        File('${directory.path}${Platform.pathSeparator}ai_providers_ayush.json')
            .existsSync(),
        isTrue,
      );
    });

    test('consent and selection survive a reload; language migrates to auto',
        () async {
      final AiPreferencesStore store =
          AiPreferencesStore(directory: directory, profile: AuraProfile.family);
      await store.save(
        const AiPreferences(
          // Simulate an older profile that stored a fixed language choice.
          language: AiLanguage.bengali,
          consentGranted: true,
          selectedProviderId: 'groq',
          activeConversationId: 'conversation-1',
        ),
      );

      final AiPreferences loaded = await AiPreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      ).load();
      expect(loaded.language, AiLanguage.auto);
      expect(loaded.consentGranted, isTrue);
      expect(loaded.selectedProviderId, 'groq');
      expect(loaded.activeConversationId, 'conversation-1');
    });

    test('AYUSH conversations are isolated and ordered by update time',
        () async {
      final AiConversationStore family = AiConversationStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final AiConversationStore ayush = AiConversationStore(
        directory: directory,
        profile: AuraProfile.ayush,
      );
      final DateTime older = DateTime(2026, 1, 1);
      final DateTime newer = DateTime(2026, 1, 2);

      await family.save(<AiConversation>[
        AiConversation(
          id: 'shared',
          title: 'Shared chat',
          updatedAt: older,
          messages: <AiMessage>[
            AiMessage(
              role: AiMessageRole.user,
              content: 'family only',
              timestamp: older,
            ),
          ],
        ),
      ]);
      await ayush.save(<AiConversation>[
        AiConversation(
          id: 'private',
          title: 'Private chat',
          updatedAt: newer,
          messages: <AiMessage>[
            AiMessage(
              role: AiMessageRole.user,
              content: 'private only',
              timestamp: newer,
            ),
          ],
        ),
      ]);

      final List<AiConversation> familyLoaded = await family.load();
      final List<AiConversation> ayushLoaded = await ayush.load();
      expect(familyLoaded, hasLength(1));
      expect(ayushLoaded, hasLength(1));
      expect(familyLoaded.single.id, 'shared');
      expect(ayushLoaded.single.id, 'private');
      expect(
        familyLoaded.single.list().single.content,
        isNot(contains('private')),
      );
      expect(
        ayushLoaded.single.list().single.content,
        isNot(contains('family')),
      );
    });

    test('conversation metadata, interrupted state and bounds round-trip',
        () async {
      final AiConversationStore store = AiConversationStore(
          directory: directory, profile: AuraProfile.family);
      AiConversation conversation = const AiConversation(
        id: 'bounded',
        title: 'Renamed chat',
        createdAt: null,
      );
      for (int index = 0;
          index < AuraRuntimeConfig.maxConversationMessages + 4;
          index++) {
        conversation = conversation.append(
          AiMessage(
            role: AiMessageRole.assistant,
            content: 'm$index',
            timestamp: DateTime(2026, 1, 1).add(Duration(seconds: index)),
            isInterrupted:
                index == AuraRuntimeConfig.maxConversationMessages + 3,
          ),
        );
      }
      await store.save(<AiConversation>[conversation]);

      final AiConversation loaded = (await store.load()).single;
      expect(loaded.title, 'Renamed chat');
      expect(loaded.length, AuraRuntimeConfig.maxConversationMessages);
      expect(loaded.displayTitle, 'Renamed chat');
      expect(loaded.list().last.isInterrupted, isTrue);
    });
  });
}
