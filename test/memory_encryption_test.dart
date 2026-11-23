import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_hub/features/memory/data/encrypted_memory_store.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/memory_repository.dart';
import 'package:aura_hub/features/memory/data/memory_settings_store.dart';
import 'package:aura_hub/features/memory/data/memory_storage_envelope.dart';
import 'package:aura_hub/features/memory/data/memory_store.dart';
import 'package:aura_hub/features/memory/data/windows_dpapi_memory_cipher.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/memory/domain/memory_status.dart';
import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _privateContent = 'A private AYUSH preference.';
const String _sharedContent = 'A shared household preference.';

class _XorCipher implements MemoryCipher {
  _XorCipher(this.key);

  final int key;
  int encryptCalls = 0;
  int decryptCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  Future<Uint8List> encrypt(List<int> plaintext) async {
    encryptCalls++;
    return Uint8List.fromList(
      plaintext.map((int byte) => (byte ^ key) & 0xff).toList(growable: false),
    );
  }

  @override
  Future<Uint8List> decrypt(List<int> ciphertext) async {
    decryptCalls++;
    return Uint8List.fromList(
      ciphertext.map((int byte) => (byte ^ key) & 0xff).toList(growable: false),
    );
  }
}

MemoryRecord _record({
  AuraProfile profile = AuraProfile.ayush,
  String id = 'mem-encrypted',
  String content = _privateContent,
}) {
  final DateTime stamp = DateTime(2026, 1, 1);
  return MemoryRecord(
    id: id,
    profile: profile,
    content: content,
    category: MemoryCategory.preference,
    status: MemoryStatus.approved,
    createdAt: stamp,
    updatedAt: stamp,
  );
}

File _file(Directory directory, String name) =>
    File('${directory.path}${Platform.pathSeparator}$name');

class _Harness {
  _Harness({int cipherKey = 7}) {
    directory = Directory.systemTemp.createTempSync('aura_memory_encryption_');
    cipher = _XorCipher(cipherKey);
    ayushStore = EncryptedMemoryStore(
      directory: directory,
      profile: AuraProfile.ayush,
      cipher: cipher,
    );
    ayushSettings = EncryptedMemorySettingsStore(
      directory: directory,
      profile: AuraProfile.ayush,
      cipher: cipher,
    );
    familyStore = MemoryStore(
      directory: directory,
      profile: AuraProfile.family,
    );
    familySettings = MemorySettingsStore(
      directory: directory,
      profile: AuraProfile.family,
    );
    session = ProfileSession.initial;
    ayush = LocalMemoryRepository(
      profile: AuraProfile.ayush,
      store: ayushStore,
      settingsStore: ayushSettings,
      accessReader: _access,
    );
    family = LocalMemoryRepository(
      profile: AuraProfile.family,
      store: familyStore,
      settingsStore: familySettings,
      accessReader: _familyAccess,
    );
  }

  ProfileAccess _access() => ProfileAccess(session);

  ProfileAccess _familyAccess() => ProfileAccess(familySession);

  late final Directory directory;
  late final _XorCipher cipher;
  late final EncryptedMemoryStore ayushStore;
  late final EncryptedMemorySettingsStore ayushSettings;
  late final MemoryStore familyStore;
  late final MemorySettingsStore familySettings;
  late final MemoryRepository ayush;
  late final MemoryRepository family;
  late ProfileSession session;
  ProfileSession familySession = ProfileSession.initial;

  File get ayushFile => _file(directory, 'memory_ayush.json');
  File get ayushSettingsFile => _file(directory, 'memory_settings_ayush.json');
  File get familyFile => _file(directory, 'memory_family.json');

  void unlockAyush() {
    session = ProfileSession(
      profile: AuraProfile.ayush,
      startedAt: DateTime(2026),
      authenticated: true,
    );
  }

  void lock() => session = ProfileSession.initial;

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

void main() {
  group('Windows DPAPI cipher', () {
    test('round-trips real encrypted bytes and rejects tampering', () async {
      if (!Platform.isWindows) return;
      final WindowsDpapiMemoryCipher cipher = WindowsDpapiMemoryCipher();
      final List<int> plaintext = utf8.encode('AURA DPAPI verification value');

      final Uint8List ciphertext = await cipher.encrypt(plaintext);
      expect(ciphertext, isNot(equals(plaintext)));
      expect(utf8.decode(await cipher.decrypt(ciphertext)),
          'AURA DPAPI verification value');

      final Uint8List tampered = Uint8List.fromList(ciphertext);
      tampered[tampered.length - 2] ^= 0xff;
      await expectLater(
        cipher.decrypt(tampered),
        throwsA(isA<MemoryStorageException>()),
      );
    });

    test('a different protection context cannot decrypt (wrong-user analogue)',
        () async {
      if (!Platform.isWindows) return;
      final WindowsDpapiMemoryCipher writer = WindowsDpapiMemoryCipher();
      final WindowsDpapiMemoryCipher otherContext = WindowsDpapiMemoryCipher(
        entropy: 'aura-hub-memory-v1-different-context',
      );
      final Uint8List ciphertext =
          await writer.encrypt(utf8.encode('protection context check'));

      await expectLater(
        otherContext.decrypt(ciphertext),
        throwsA(isA<MemoryStorageException>()),
      );
    });
  });

  group('Encrypted AYUSH storage', () {
    test('stores only an encrypted envelope and survives a restart', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      expect(
        (await harness.ayush.createApproved(
          content: _privateContent,
          category: MemoryCategory.preference,
        ))
            .isSuccess,
        isTrue,
      );
      await harness.ayush.saveSettings(
        const MemorySettings(retrievalEnabled: true),
      );

      final String raw = harness.ayushFile.readAsStringSync();
      final String settingsRaw = harness.ayushSettingsFile.readAsStringSync();
      expect(raw, contains(MemoryStorageEnvelope.versionKey));
      expect(settingsRaw, contains(MemoryStorageEnvelope.versionKey));
      expect(raw, isNot(contains(_privateContent)));

      final EncryptedMemoryStore reloaded = EncryptedMemoryStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      );
      final EncryptedMemorySettingsStore reloadedSettings =
          EncryptedMemorySettingsStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      );

      expect((await reloaded.load()).single.content, _privateContent);
      expect((await reloadedSettings.load()).retrievalEnabled, isTrue);
    });

    test('migrates validated legacy plaintext and removes its backup',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      final MemoryStore legacyStore = MemoryStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
      );
      final MemorySettingsStore legacySettings = MemorySettingsStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
      );
      await legacyStore.save(<MemoryRecord>[_record()]);
      await legacySettings.save(
        const MemorySettings(retrievalEnabled: true),
      );
      expect(harness.ayushFile.readAsStringSync(), contains(_privateContent));

      expect((await harness.ayushStore.load()).single.content, _privateContent);
      expect((await harness.ayushSettings.load()).retrievalEnabled, isTrue);

      final String raw = harness.ayushFile.readAsStringSync();
      expect(raw, contains(MemoryStorageEnvelope.versionKey));
      expect(raw, isNot(contains(_privateContent)));
      expect(
        _file(harness.directory, 'memory_ayush.json.legacy.backup')
            .existsSync(),
        isFalse,
      );
    });

    test('interrupted migration preserves the original and retries cleanly',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      final MemoryStore legacyStore = MemoryStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
      );
      await legacyStore.save(<MemoryRecord>[_record()]);
      final String original = harness.ayushFile.readAsStringSync();
      bool interrupt = true;
      final EncryptedMemoryStore interruptedStore = EncryptedMemoryStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
        beforeMigrationCommit: () async {
          if (interrupt) throw StateError('simulated write interruption');
        },
      );

      await expectLater(
        interruptedStore.load(),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(harness.ayushFile.readAsStringSync(), original);
      expect(
        _file(harness.directory, 'memory_ayush.json.legacy.backup')
            .existsSync(),
        isTrue,
      );

      final EncryptedMemoryStore retryStore = EncryptedMemoryStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      );
      expect((await retryStore.load()).single.content, _privateContent);
      expect(harness.ayushFile.readAsStringSync(), isNot(original));
      expect(
        _file(harness.directory, 'memory_ayush.json.legacy.backup')
            .existsSync(),
        isFalse,
      );
    });

    test('wrong-user decryption fails closed and never overwrites data',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      await harness.ayush.createApproved(
        content: _privateContent,
        category: MemoryCategory.preference,
      );
      final String original = harness.ayushFile.readAsStringSync();

      final _XorCipher wrongUserCipher = _XorCipher(99);
      final LocalMemoryRepository wrongUserRepository = LocalMemoryRepository(
        profile: AuraProfile.ayush,
        store: EncryptedMemoryStore(
          directory: harness.directory,
          profile: AuraProfile.ayush,
          cipher: wrongUserCipher,
        ),
        settingsStore: EncryptedMemorySettingsStore(
          directory: harness.directory,
          profile: AuraProfile.ayush,
          cipher: wrongUserCipher,
        ),
        accessReader: () => ProfileAccess(harness.session),
      );

      expect(await wrongUserRepository.load(), isEmpty);
      expect(
        wrongUserRepository.storageErrorMessage,
        contains('could not be decrypted'),
      );
      final MemoryWriteResult write = await wrongUserRepository.createApproved(
        content: 'This must never be persisted.',
        category: MemoryCategory.personalFact,
      );
      expect(write.outcome, MemoryWriteOutcome.storageSecurityError);
      expect(harness.ayushFile.readAsStringSync(), original);
      expect(
        wrongUserRepository.storageErrorMessage,
        isNot(contains('This must never be persisted.')),
      );
    });

    test('tampered ciphertext is rejected without replacement', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      await harness.ayushStore.save(<MemoryRecord>[_record()]);
      final Map<String, dynamic> envelope =
          jsonDecode(harness.ayushFile.readAsStringSync())
              as Map<String, dynamic>;
      final Uint8List payload = Uint8List.fromList(
        base64.decode(envelope[MemoryStorageEnvelope.payloadKey] as String),
      );
      payload[0] ^= 0xff;
      final String tampered = MemoryStorageEnvelope.encode(
        ciphertext: payload,
        scope: AuraProfile.ayush.storageScope,
      );
      harness.ayushFile.writeAsStringSync(tampered);

      await expectLater(
        harness.ayushStore.load(),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(harness.ayushFile.readAsStringSync(), tampered);
    });

    test(
        'missing files stay empty; corrupt or invalid-schema files fail closed',
        () async {
      final _Harness missing = _Harness();
      addTearDown(missing.dispose);
      expect(await missing.ayushStore.load(), isEmpty);
      final MemorySettings missingSettings = await missing.ayushSettings.load();
      expect(missingSettings.retrievalEnabled, isFalse);
      expect(missingSettings.suggestionsEnabled, isTrue);
      expect(missing.ayushFile.existsSync(), isFalse);

      final _Harness corrupt = _Harness();
      addTearDown(corrupt.dispose);
      const String broken = '{not valid json';
      corrupt.ayushFile.writeAsStringSync(broken);
      await expectLater(
        corrupt.ayushStore.load(),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(corrupt.ayushFile.readAsStringSync(), broken);

      corrupt.ayushFile.writeAsStringSync(
        jsonEncode(<String, dynamic>{'unexpected': true}),
      );
      final String invalid = corrupt.ayushFile.readAsStringSync();
      await expectLater(
        corrupt.ayushStore.load(),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(corrupt.ayushFile.readAsStringSync(), invalid);
    });

    test('unsupported encryption never falls back to plaintext', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      final EncryptedMemoryStore unsupported = EncryptedMemoryStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: const UnsupportedMemoryCipher(),
      );
      await expectLater(
        unsupported.load(),
        throwsA(isA<MemoryStorageException>()),
      );
      await expectLater(
        unsupported.save(<MemoryRecord>[_record()]),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(harness.ayushFile.existsSync(), isFalse);

      await harness.ayushStore.save(<MemoryRecord>[_record()]);
      final String encrypted = harness.ayushFile.readAsStringSync();
      await expectLater(
        unsupported.load(),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(harness.ayushFile.readAsStringSync(), encrypted);
    });

    test('FAMILY stays plaintext and shares no data with AYUSH', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      await harness.ayush.createApproved(
        content: _privateContent,
        category: MemoryCategory.personalFact,
      );
      await harness.family.createApproved(
        content: _sharedContent,
        category: MemoryCategory.familyInformation,
      );

      expect(harness.familyFile.readAsStringSync(), contains(_sharedContent));
      expect(harness.ayushFile.readAsStringSync(),
          isNot(contains(_privateContent)));

      expect(
        (await harness.family.load()).map((MemoryRecord item) => item.content),
        <String>[_sharedContent],
      );
      expect(
        (await harness.ayush.load()).map((MemoryRecord item) => item.content),
        <String>[_privateContent],
      );
    });

    test('locking clears decrypted AYUSH state and unlock reloads it',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      harness.unlockAyush();

      await harness.ayush.createApproved(
        content: _privateContent,
        category: MemoryCategory.preference,
      );
      expect(await harness.ayush.load(), hasLength(1));

      harness.lock();
      harness.ayush.discardForLock();
      expect(await harness.ayush.load(), isEmpty);

      harness.unlockAyush();
      expect((await harness.ayush.load()).single.content, _privateContent);
    });

    test('controller surfaces a clear recovery error', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      await harness.ayushStore.save(<MemoryRecord>[_record()]);
      final LocalMemoryRepository failingRepository = LocalMemoryRepository(
        profile: AuraProfile.ayush,
        store: EncryptedMemoryStore(
          directory: harness.directory,
          profile: AuraProfile.ayush,
          cipher: _XorCipher(42),
        ),
        settingsStore: EncryptedMemorySettingsStore(
          directory: harness.directory,
          profile: AuraProfile.ayush,
          cipher: _XorCipher(42),
        ),
        accessReader: () => ProfileAccess(harness.session),
      );
      harness.unlockAyush();

      final MemoryController controller = MemoryController(
        failingRepository,
        accessReader: () => ProfileAccess(harness.session),
      );
      addTearDown(controller.dispose);
      await controller.load();

      expect(controller.state.storageError, isTrue);
      expect(
        controller.state.errorMessage,
        contains('could not be decrypted'),
      );
      expect(controller.state.records, isEmpty);
    });

    test('providers select encrypted AYUSH stores and plaintext FAMILY stores',
        () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          ayushMemoryCipherProvider.overrideWithValue(_XorCipher(3)),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(memoryStoreForProvider(AuraProfile.ayush)),
        isA<EncryptedMemoryStore>(),
      );
      expect(
        container.read(memorySettingsStoreForProvider(AuraProfile.ayush)),
        isA<EncryptedMemorySettingsStore>(),
      );
      expect(
        container.read(memoryStoreForProvider(AuraProfile.family)),
        isA<MemoryStore>(),
      );
      expect(
        container.read(memorySettingsStoreForProvider(AuraProfile.family)),
        isA<MemorySettingsStore>(),
      );
    });
  });
}
