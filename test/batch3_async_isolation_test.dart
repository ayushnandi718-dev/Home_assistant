import 'dart:async';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/ai/data/ai_config_store.dart';
import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/data/ai_preferences_store.dart';
import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';
import 'package:aura_hub/features/ai/domain/ai_tool.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/family/data/family_directory_repository.dart';
import 'package:aura_hub/features/family/domain/family_member.dart';
import 'package:aura_hub/features/family/domain/family_relationship.dart';
import 'package:aura_hub/features/family/presentation/family_providers.dart';
import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/memory/data/memory_repository.dart';
import 'package:aura_hub/features/memory/data/memory_settings_store.dart';
import 'package:aura_hub/features/memory/data/memory_store.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/security/data/ayush_security_settings_store.dart';
import 'package:aura_hub/features/security/domain/ayush_security_settings.dart';
import 'package:aura_hub/features/security/presentation/security_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Mutable session source used to advance generations at exact await points.
class SessionHub {
  ProfileSession _session = ProfileSession.initial;

  ProfileAccess get access => ProfileAccess(_session);
  ProfileAccessReader get reader => () => access;
  ProfileSession get session => _session;

  void unlockAyush() {
    _session = ProfileSession(
      profile: AuraProfile.ayush,
      startedAt: DateTime(2026),
      authenticated: true,
      generation: _session.generation + 1,
    );
  }

  void openFamily() {
    _session = ProfileSession(
      profile: AuraProfile.family,
      startedAt: DateTime(2026),
      authenticated: false,
      generation: _session.generation + 1,
    );
  }
}

class MemoryPinFile implements ProfilePinFile {
  String _contents = '';

  @override
  Future<bool> exists() async => _contents.isNotEmpty;

  @override
  Future<String> readAsString() async => _contents;

  @override
  Future<void> writeAsString(String contents, {required bool flush}) async =>
      _contents = contents;

  @override
  Future<void> replaceWith(
    String contents, {
    bool Function()? isCommitAllowed,
  }) async {
    if (isCommitAllowed != null && !isCommitAllowed()) return;
    _contents = contents;
  }

  @override
  Future<void> createParent() async {}

  @override
  Future<void> delete() async => _contents = '';
}

/// PIN store with a controllable verification boundary for lock-race tests.
/// Production still uses PBKDF2-HMAC-SHA256 with 600,000 iterations.
class GatedPinStore extends ProfilePinStore {
  GatedPinStore()
      : super(
          file: MemoryPinFile(),
          lockoutFile: MemoryPinFile(),
          iterations: 1000,
        );

  String _pin = '1111';
  final Completer<bool> verifyGate = Completer<bool>();
  final Completer<void> setGate = Completer<void>();
  bool gateNextVerify = false;
  bool gateNextSet = false;

  @override
  Future<bool> hasPin() async => true;

  @override
  Future<bool> verify(
    String pin, {
    bool Function()? isCommitAllowed,
  }) async {
    if (gateNextVerify) {
      gateNextVerify = false;
      await verifyGate.future;
    }
    if (isCommitAllowed != null && !isCommitAllowed()) {
      throw const AuraProfileAccessDenied(AuraProfile.ayush);
    }
    return pin == _pin;
  }

  @override
  Future<void> setPin(
    String pin, {
    bool Function()? isCommitAllowed,
  }) async {
    if (gateNextSet) {
      gateNextSet = false;
      await setGate.future;
    }
    if (isCommitAllowed != null && !isCommitAllowed()) {
      throw const AuraProfileAccessDenied(AuraProfile.ayush);
    }
    _pin = pin;
  }

  String get currentPin => _pin;
}

/// File seam that gates the actual verifier replacement, not just hashing.
/// It mirrors the production boundary by checking ownership synchronously
/// after the gate releases and before mutating the stored verifier.
class GatedPinFile implements ProfilePinFile {
  String _contents = '';
  final Completer<void> replaceStarted = Completer<void>();
  final Completer<void> replaceGate = Completer<void>();
  bool gateNextReplace = false;
  int replaceAttempts = 0;

  @override
  Future<bool> exists() async => _contents.isNotEmpty;

  @override
  Future<String> readAsString() async => _contents;

  @override
  Future<void> writeAsString(String contents, {required bool flush}) async =>
      _contents = contents;

  @override
  Future<void> replaceWith(
    String contents, {
    bool Function()? isCommitAllowed,
  }) async {
    replaceAttempts++;
    if (gateNextReplace) {
      gateNextReplace = false;
      if (!replaceStarted.isCompleted) replaceStarted.complete();
      await replaceGate.future;
    }
    if (isCommitAllowed != null && !isCommitAllowed()) {
      throw const AuraProfileAccessDenied(AuraProfile.ayush);
    }
    _contents = contents;
  }

  @override
  Future<void> createParent() async {}

  @override
  Future<void> delete() async => _contents = '';

  String get contents => _contents;
}

class MemoryVault implements CredentialVault {
  final Map<String, String> secrets = <String, String>{};
  int writes = 0;

  @override
  Future<void> write(
      {required String target,
      required String secret,
      bool Function()? isCommitAllowed}) async {
    writes++;
    secrets[target] = secret;
  }

  @override
  Future<String?> read({required String target}) async => secrets[target];

  @override
  Future<bool> delete(
          {required String target, bool Function()? isCommitAllowed}) async =>
      secrets.remove(target) != null;
}

class GatedAiClient implements AiClient {
  final Completer<void> started = Completer<void>();
  final StreamController<String> controller = StreamController<String>();
  int callCount = 0;

  @override
  Stream<String> streamCompletion({
    required AiProviderConfig config,
    required List<AiMessage> messages,
    List<AiToolDefinition> tools = const <AiToolDefinition>[],
    AiLanguage language = AiLanguage.english,
    AiRequestContext? context,
  }) {
    callCount++;
    if (!started.isCompleted) started.complete();
    return controller.stream;
  }

  @override
  Future<void> testConnection({
    required AiProviderConfig config,
    AiRequestContext? context,
  }) async {}

  void dispose() {
    if (!controller.isClosed) controller.close();
  }
}

class MemoryConfigStore extends AiConfigStore {
  MemoryConfigStore() : super(profile: AuraProfile.ayush);

  List<AiProviderConfig> configs = const <AiProviderConfig>[];

  @override
  Future<List<AiProviderConfig>> load() async => configs;

  @override
  Future<void> save(List<AiProviderConfig> values) async => configs = values;

  @override
  Future<List<AiProviderConfig>> upsert(AiProviderConfig config) async {
    configs = <AiProviderConfig>[
      config,
      ...configs.where((AiProviderConfig item) => item.id != config.id),
    ];
    return configs;
  }
}

class MemoryPreferencesStore extends AiPreferencesStore {
  MemoryPreferencesStore() : super(profile: AuraProfile.ayush);

  AiPreferences preferences = const AiPreferences();
  final List<AiPreferences> saves = <AiPreferences>[];
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> saveGate = Completer<void>();
  bool gated = false;
  bool _firstSave = true;

  @override
  Future<AiPreferences> load() async => preferences;

  @override
  Future<void> save(
    AiPreferences value, {
    bool Function()? isWriteAllowed,
  }) async {
    if (gated && _firstSave) {
      _firstSave = false;
      if (!saveStarted.isCompleted) saveStarted.complete();
      await saveGate.future;
    }
    if (isWriteAllowed != null && !isWriteAllowed()) return;
    saves.add(value);
    preferences = value;
  }
}

class GatedConversationRepository implements AiConversationRepository {
  @override
  AuraProfile get profile => AuraProfile.ayush;

  final List<AiConversation> conversations = <AiConversation>[];
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> saveGate = Completer<void>();
  int saves = 0;
  bool _firstSave = true;

  @override
  Future<AiConversationLoadResult> load() async =>
      AiConversationLoadResult.ready(List<AiConversation>.from(conversations));

  @override
  Future<void> save(List<AiConversation> next) async {
    saves++;
    if (_firstSave) {
      _firstSave = false;
      if (!saveStarted.isCompleted) saveStarted.complete();
      await saveGate.future;
    }
    conversations
      ..clear()
      ..addAll(next);
  }

  @override
  Future<void> clearSession() async => conversations.clear();
}

class GatedMemoryStore implements MemoryRecordStore {
  @override
  AuraProfile get profile => AuraProfile.ayush;

  List<MemoryRecord> records = const <MemoryRecord>[];
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> saveGate = Completer<void>();
  bool _firstSave = true;

  @override
  Future<List<MemoryRecord>> load({bool Function()? isWriteAllowed}) async =>
      records;

  @override
  Future<bool> save(
    List<MemoryRecord> next, {
    bool Function()? isWriteAllowed,
  }) async {
    if (_firstSave) {
      _firstSave = false;
      if (!saveStarted.isCompleted) saveStarted.complete();
      await saveGate.future;
    }
    // The real encrypted/plaintext stores repeat this check at the atomic
    // commit boundary; the fake mirrors that contract.
    if (isWriteAllowed != null && !isWriteAllowed()) return false;
    records = List<MemoryRecord>.unmodifiable(next);
    return true;
  }
}

class MemorySettingsStorageFake implements MemorySettingsStorage {
  MemorySettings settings = const MemorySettings(suggestionsEnabled: true);

  @override
  Future<MemorySettings> load({bool Function()? isWriteAllowed}) async =>
      settings;

  @override
  Future<bool> save(
    MemorySettings value, {
    bool Function()? isWriteAllowed,
  }) async {
    if (isWriteAllowed != null && !isWriteAllowed()) return false;
    settings = value;
    return true;
  }
}

class GatedFamilyRepository implements FamilyDirectoryRepository {
  List<FamilyMember> members = const <FamilyMember>[];
  final Completer<void> upsertStarted = Completer<void>();
  final Completer<void> upsertGate = Completer<void>();

  @override
  Future<List<FamilyMember>> load() async => members;

  @override
  Future<List<FamilyMember>> upsert(FamilyMember member) async {
    if (!upsertStarted.isCompleted) upsertStarted.complete();
    await upsertGate.future;
    members = <FamilyMember>[member, ...members];
    return members;
  }

  @override
  Future<List<FamilyMember>> remove(String id) async =>
      members = members.where((FamilyMember item) => item.id != id).toList();

  @override
  Future<List<FamilyMember>> replaceAll(List<FamilyMember> next) async =>
      members = next;
}

class GatedSecurityStorage implements AyushSecuritySettingsStorage {
  AyushSecuritySettings stored = AyushSecuritySettings.defaults;
  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> saveGate = Completer<void>();

  @override
  Future<AyushSecuritySettings> load({bool Function()? isWriteAllowed}) async =>
      stored;

  @override
  Future<void> save(
    AyushSecuritySettings settings, {
    bool Function()? isWriteAllowed,
  }) async {
    if (!saveStarted.isCompleted) saveStarted.complete();
    await saveGate.future;
    if (isWriteAllowed != null && !isWriteAllowed()) {
      throw const AuraProfileAccessDenied(AuraProfile.ayush);
    }
    stored = settings;
  }
}

Future<void> _waitFor(Future<void> future) => future.timeout(
      const Duration(seconds: 5),
      onTimeout: () => fail('Deterministic gate was never released.'),
    );

void main() {
  group('Batch 3 deterministic async isolation', () {
    test('session generation is part of operation ownership', () {
      final SessionHub hub = SessionHub();
      final ProfileOperationOwner owner = ProfileOperationOwner(
        accessReader: hub.reader,
        profile: AuraProfile.family,
      );

      hub.openFamily();

      expect(owner.isCurrent, isFalse);
      expect(
        () => owner.requireCurrent(),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
    });

    test('a lock during streaming never publishes or persists a late reply',
        () async {
      final SessionHub hub = SessionHub()..unlockAyush();
      final MemoryConfigStore configStore = MemoryConfigStore();
      final MemoryPreferencesStore preferenceStore = MemoryPreferencesStore();
      final GatedConversationRepository conversationRepository =
          GatedConversationRepository();
      final MemoryVault vault = MemoryVault();
      final GatedAiClient client = GatedAiClient();
      addTearDown(client.dispose);

      final AiConfigController configs = AiConfigController(
        profile: AuraProfile.ayush,
        store: configStore,
        accessReader: hub.reader,
      );
      addTearDown(configs.dispose);
      await configs.upsert(
        const AiProviderConfig(
          id: 'groq',
          label: 'Groq',
          kind: AiProviderKind.openAiCompatible,
          baseUrl: 'https://api.groq.com/openai/v1',
          model: 'private-model',
          enabled: true,
        ),
      );

      final AiPreferencesController preferences = AiPreferencesController(
        profile: AuraProfile.ayush,
        store: preferenceStore,
        accessReader: hub.reader,
      );
      addTearDown(preferences.dispose);
      await preferences.load();
      await preferences.setConsent(true);

      final AiConversationLibraryController conversations =
          AiConversationLibraryController(
        profile: AuraProfile.ayush,
        repository: conversationRepository,
        accessReader: hub.reader,
      );
      addTearDown(conversations.dispose);
      final String conversationId = conversations.create();
      await preferences.setActiveConversation(conversationId);

      final AiCredentialController credentials = AiCredentialController(
        profile: AuraProfile.ayush,
        store: AiCredentialStore(vault: vault),
        accessReader: hub.reader,
      );
      addTearDown(credentials.dispose);
      await credentials.save(providerId: 'groq', apiKey: 'FAKE-PRIVATE-KEY');

      final AiChatController chat = AiChatController(
        profile: AuraProfile.ayush,
        access: hub.access,
        accessReader: hub.reader,
        configs: configs,
        preferences: preferences,
        conversations: conversations,
        credentials: credentials,
        client: client,
        logger: AuraLogger(),
      );
      addTearDown(chat.dispose);

      final Future<void> sending = chat.send('private prompt');
      expect(
        chat.state.isBusy,
        isTrue,
        reason: chat.state.errorMessage ?? 'send did not start',
      );
      await _waitFor(client.started.future);

      hub.openFamily();
      chat.discardForLock();
      client.controller
        ..add('LATE-PRIVATE-REPLY')
        ..close();
      await _waitFor(sending);

      expect(client.callCount, 1);
      final List<AiMessage> storedMessages =
          conversationRepository.conversations.single.list();
      expect(storedMessages, hasLength(1));
      expect(storedMessages.single.content, 'private prompt');
      expect(
        storedMessages.map((AiMessage message) => message.content),
        isNot(contains('LATE-PRIVATE-REPLY')),
      );
      expect(conversations.state.single.list(), hasLength(1));
      expect(chat.state.streamingText, isNull);
    });

    test('a stale setConsent does not overwrite newer preferences', () async {
      final SessionHub hub = SessionHub()..unlockAyush();
      final MemoryPreferencesStore store = MemoryPreferencesStore()
        ..gated = true;
      final AiPreferencesController preferences = AiPreferencesController(
        profile: AuraProfile.ayush,
        store: store,
        accessReader: hub.reader,
      );
      addTearDown(preferences.dispose);
      await preferences.load();

      final Future<void> granting = preferences.setConsent(true);
      await _waitFor(store.saveStarted.future);

      hub.openFamily();
      preferences.discardForLock();
      store.saveGate.complete();

      await expectLater(
        granting,
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      expect(store.saves, isEmpty);
      expect(preferences.state.consentGranted, isFalse);
    });

    test('a memory suggestion locked during commit does not reach storage',
        () async {
      final SessionHub hub = SessionHub()..unlockAyush();
      final GatedMemoryStore store = GatedMemoryStore();
      final MemorySettingsStorageFake settingsStore =
          MemorySettingsStorageFake();
      final LocalMemoryRepository repository = LocalMemoryRepository(
        profile: AuraProfile.ayush,
        store: store,
        settingsStore: settingsStore,
        accessReader: hub.reader,
      );
      final MemoryController controller = MemoryController(
        repository,
        accessReader: hub.reader,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final Future<bool> suggesting = controller.suggest(
        content: 'PRIVATE-MEMORY-PENDING',
        category: MemoryCategory.preference,
      );
      await _waitFor(store.saveStarted.future);

      hub.openFamily();
      controller.discardForLock();
      store.saveGate.complete();
      expect(await suggesting, isFalse);

      expect(store.records, isEmpty);
      expect(controller.state.records, isEmpty);
      expect(controller.state.errorMessage, isNull);
    });

    test('a FAMILY directory result after a profile switch is not published',
        () async {
      final SessionHub hub = SessionHub();
      final GatedFamilyRepository repository = GatedFamilyRepository();
      final FamilyDirectoryController controller = FamilyDirectoryController(
        repository,
        accessReader: hub.reader,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final DateTime stamp = DateTime(2026);
      final Future<void> adding = controller.add(
        FamilyMember(
          id: 'family-1',
          fullName: 'Family Member',
          relationship: FamilyRelationship.mother,
          createdAt: stamp,
          updatedAt: stamp,
        ),
      );
      await _waitFor(repository.upsertStarted.future);

      hub.unlockAyush();
      controller.discardForProfileSwitch();
      repository.upsertGate.complete();
      await _waitFor(adding);

      expect(controller.state, isEmpty);
      expect(repository.members, hasLength(1));
    });

    test('a private settings save locked at commit keeps the safe value',
        () async {
      final SessionHub hub = SessionHub()..unlockAyush();
      final GatedSecurityStorage storage = GatedSecurityStorage();
      final AyushSecuritySettingsController controller =
          AyushSecuritySettingsController(
        store: storage,
        accessReader: hub.reader,
      );
      addTearDown(controller.dispose);
      await controller.load();

      final Future<void> saving = controller.update(AyushAutoLock.never);
      await _waitFor(storage.saveStarted.future);

      hub.openFamily();
      controller.clear();
      storage.saveGate.complete();
      await _waitFor(saving);

      expect(storage.stored.autoLock, AyushAutoLock.fiveMinutes);
      expect(controller.state.settings.autoLock, AyushAutoLock.fiveMinutes);
      expect(controller.state.error, isNull);
    });

    test('a PIN change whose verification outlives the session fails closed',
        () async {
      final GatedPinStore store = GatedPinStore();
      final ProfileSessionController controller = ProfileSessionController(
        store: store,
        logger: AuraLogger(),
      );
      addTearDown(controller.dispose);
      await controller.lockoutReady;
      await controller.setupPin('1111');

      store.gateNextVerify = true;
      final Future<PinChangeResult> changing = controller.changePin(
        currentPin: '1111',
        newPin: '2222',
        confirmation: '2222',
      );
      await Future<void>.delayed(Duration.zero);

      controller.lock();
      store.verifyGate.complete(true);

      expect(await changing, PinChangeResult.profileLocked);
      expect(store.currentPin, '1111');
      expect(controller.state.profile, AuraProfile.family);
      expect(controller.state.privateSessionActive, isFalse);
    });

    test('a PIN setup locked at the atomic commit keeps the old verifier',
        () async {
      final GatedPinFile file = GatedPinFile();
      final ProfilePinStore store = ProfilePinStore(
        file: file,
        lockoutFile: MemoryPinFile(),
        iterations: 1000,
      );
      final ProfileSessionController controller = ProfileSessionController(
        store: store,
        logger: AuraLogger(),
      );
      addTearDown(controller.dispose);
      await controller.lockoutReady;
      expect(await controller.setupPin('1111'), ProfileUnlockResult.success);
      final String originalVerifier = file.contents;

      file.gateNextReplace = true;
      final Future<ProfileUnlockResult> setting = controller.setupPin('2222');
      await file.replaceStarted.future;
      controller.openFamily();
      file.replaceGate.complete();

      expect(await setting, ProfileUnlockResult.unavailable);
      expect(file.replaceAttempts, 2);
      expect(file.contents, originalVerifier);
      expect(await store.verify('1111'), isTrue);
      expect(await store.verify('2222'), isFalse);
    });

    test('a PIN change locked at the atomic commit keeps the old verifier',
        () async {
      final GatedPinFile file = GatedPinFile();
      final ProfilePinStore store = ProfilePinStore(
        file: file,
        lockoutFile: MemoryPinFile(),
        iterations: 1000,
      );
      final ProfileSessionController controller = ProfileSessionController(
        store: store,
        logger: AuraLogger(),
      );
      addTearDown(controller.dispose);
      await controller.lockoutReady;
      expect(await controller.setupPin('1111'), ProfileUnlockResult.success);
      final String originalVerifier = file.contents;

      file.gateNextReplace = true;
      final Future<PinChangeResult> changing = controller.changePin(
        currentPin: '1111',
        newPin: '2222',
        confirmation: '2222',
      );
      await file.replaceStarted.future;
      controller.lock();
      file.replaceGate.complete();

      expect(await changing, PinChangeResult.profileLocked);
      expect(file.replaceAttempts, 2);
      expect(file.contents, originalVerifier);
      expect(await store.verify('1111'), isTrue);
      expect(await store.verify('2222'), isFalse);
      expect(controller.state.privateSessionActive, isFalse);
    });

    test('a lockout write that outlives the session is rejected at commit',
        () async {
      final GatedPinFile verifier = GatedPinFile();
      final GatedPinFile lockout = GatedPinFile();
      final ProfilePinStore store = ProfilePinStore(
        file: verifier,
        lockoutFile: lockout,
        iterations: 1000,
      );
      final ProfileSessionController controller = ProfileSessionController(
        store: store,
        logger: AuraLogger(),
      );
      addTearDown(controller.dispose);
      await controller.lockoutReady;
      expect(await controller.setupPin('1111'), ProfileUnlockResult.success);
      final String originalLockout = lockout.contents;

      lockout.gateNextReplace = true;
      final Future<ProfileUnlockResult> unlocking =
          controller.unlockAyush('9999');
      await lockout.replaceStarted.future;
      controller.openFamily();
      lockout.replaceGate.complete();

      expect(await unlocking, ProfileUnlockResult.unavailable);
      expect(lockout.contents, originalLockout);
      expect(controller.state.privateSessionActive, isFalse);
    });

    test('credential writes refuse a stale owner at the storage boundary',
        () async {
      final SessionHub hub = SessionHub()..unlockAyush();
      final MemoryVault vault = MemoryVault();
      final AiCredentialStore store = AiCredentialStore(vault: vault);
      final ProfileOperationOwner owner = ProfileOperationOwner(
        accessReader: hub.reader,
        profile: AuraProfile.ayush,
      );

      hub.openFamily();

      await expectLater(
        store.save(
          profileScope: AuraProfile.ayush.storageScope,
          providerId: 'groq',
          apiKey: 'MUST-NOT-BE-STORED',
          isWriteAllowed: () => owner.isCurrent,
        ),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      expect(vault.writes, 0);
      expect(vault.secrets, isEmpty);
    });
  });
}
