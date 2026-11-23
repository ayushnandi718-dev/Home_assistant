import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/memory_storage_envelope.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/security/data/ayush_security_settings_store.dart';
import 'package:aura_hub/features/security/domain/ayush_security_settings.dart';
import 'package:aura_hub/features/security/presentation/security_providers.dart';
import 'package:flutter_test/flutter_test.dart';

class _XorCipher implements MemoryCipher {
  const _XorCipher(this.key);

  final int key;

  @override
  bool get isAvailable => true;

  @override
  Future<Uint8List> encrypt(List<int> plaintext) async => Uint8List.fromList(
        plaintext
            .map((int byte) => (byte ^ key) & 0xff)
            .toList(growable: false),
      );

  @override
  Future<Uint8List> decrypt(List<int> ciphertext) async => Uint8List.fromList(
        ciphertext
            .map((int byte) => (byte ^ key) & 0xff)
            .toList(growable: false),
      );
}

class _FakeStorage implements AyushSecuritySettingsStorage {
  bool failLoad = false;
  bool failSave = false;
  AyushSecuritySettings stored = AyushSecuritySettings.defaults;

  @override
  Future<AyushSecuritySettings> load() async {
    if (failLoad) throw StateError('simulated read failure');
    return stored;
  }

  @override
  Future<void> save(AyushSecuritySettings settings) async {
    if (failSave) throw StateError('simulated write failure');
    stored = settings;
  }
}

File _file(Directory directory) => File(
      '${directory.path}${Platform.pathSeparator}ayush_security_settings.json',
    );

AyushSecuritySettingsStorage _store(Directory directory, MemoryCipher cipher) =>
    EncryptedAyushSecuritySettingsStore(directory: directory, cipher: cipher);

void main() {
  group('AYUSH security settings domain', () {
    test('corrupt, unknown and future values fall back to the safe default',
        () {
      expect(
          AyushSecuritySettings.fromJson(null), AyushSecuritySettings.defaults);
      expect(AyushSecuritySettings.fromJson(<String, dynamic>{}),
          AyushSecuritySettings.defaults);
      expect(
        AyushSecuritySettings.fromJson(<String, dynamic>{
          'schema': AyushSecuritySettings.schemaVersion + 1,
          'autoLock': 'never',
        }),
        AyushSecuritySettings.defaults,
      );
      expect(
        AyushSecuritySettings.fromJson(<String, dynamic>{'autoLock': 'always'}),
        AyushSecuritySettings.defaults,
      );
      expect(
        AyushSecuritySettings.fromJson(<String, dynamic>{'autoLock': 5}),
        AyushSecuritySettings.defaults,
      );
      expect(
          AyushSecuritySettings.fromJson(<String, dynamic>{
            'schema': AyushSecuritySettings.schemaVersion,
            'autoLock': 'never',
          }).autoLock,
          AyushAutoLock.never,
          reason: 'Never is an explicit choice, not a corruption fallback');
      expect(
        AyushSecuritySettings.fromJson(<String, dynamic>{
          'schema': 1,
          'autoLock': 'never',
        }).backgroundLockGrace,
        AyushBackgroundLockGrace.thirtySeconds,
        reason: 'legacy schema 1 gains the short default background grace',
      );
      expect(
        AyushSecuritySettings.fromJson(<String, dynamic>{
          'schema': AyushSecuritySettings.schemaVersion,
          'autoLock': 'never',
          'backgroundLockGrace': 'oneMinute',
        }).backgroundLockGrace,
        AyushBackgroundLockGrace.oneMinute,
      );
      expect(
        AyushSecuritySettings.fromJson(<String, dynamic>{
          'schema': AyushSecuritySettings.schemaVersion,
          'autoLock': 'never',
          'backgroundLockGrace': 'definitelyNever',
        }).backgroundLockGrace,
        AyushBackgroundLockGrace.thirtySeconds,
        reason: 'background grace has no disable value',
      );
    });

    test('all supported intervals expose the expected durations', () {
      expect(AyushAutoLock.never.duration, isNull);
      expect(AyushAutoLock.oneMinute.duration, const Duration(minutes: 1));
      expect(AyushAutoLock.fiveMinutes.duration, const Duration(minutes: 5));
      expect(AyushAutoLock.tenMinutes.duration, const Duration(minutes: 10));
      expect(
        AyushAutoLock.fifteenMinutes.duration,
        const Duration(minutes: 15),
      );
      expect(AyushAutoLock.thirtyMinutes.duration, const Duration(minutes: 30));
      expect(
        AyushSecuritySettings.defaults.autoLock,
        AyushAutoLock.fiveMinutes,
      );
    });

    test('background grace is short, bounded and non-disableable', () {
      expect(AyushBackgroundLockGrace.immediate.duration, Duration.zero);
      expect(
        AyushBackgroundLockGrace.fifteenSeconds.duration,
        const Duration(seconds: 15),
      );
      expect(
        AyushBackgroundLockGrace.thirtySeconds.duration,
        const Duration(seconds: 30),
      );
      expect(
        AyushBackgroundLockGrace.oneMinute.duration,
        const Duration(minutes: 1),
      );
      expect(
        AyushSecuritySettings.defaults.backgroundLockGrace,
        AyushBackgroundLockGrace.thirtySeconds,
      );
      expect(
        AyushBackgroundLockGrace.values
            .map((AyushBackgroundLockGrace grace) => grace.name),
        isNot(contains('never')),
      );
    });

    test('payload validation rejects future schemas and missing autoLock', () {
      expect(
          AyushSecuritySettings.isValidPayload(<String, dynamic>{
            'schema': 1,
            'autoLock': 'tenMinutes',
          }),
          isTrue,
          reason: 'schema 1 is migrated with the default background grace');
      expect(
          AyushSecuritySettings.isValidPayload(<String, dynamic>{
            'schema': AyushSecuritySettings.schemaVersion,
            'autoLock': 'never',
            'backgroundLockGrace': 'oneMinute',
          }),
          isTrue);
      expect(
          AyushSecuritySettings.isValidPayload(<String, dynamic>{
            'schema': AyushSecuritySettings.schemaVersion + 1,
            'autoLock': 'never',
          }),
          isFalse);
      expect(
          AyushSecuritySettings.isValidPayload(<String, dynamic>{
            'schema': 1,
          }),
          isFalse);
      expect(AyushSecuritySettings.isValidPayload('never'), isFalse);
    });
  });

  group('encrypted AYUSH security settings store', () {
    late Directory directory;
    late File file;
    const _XorCipher cipher = _XorCipher(7);

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('aura_ayush_security_');
      file = _file(directory);
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('missing file uses the safe default without creating plaintext',
        () async {
      expect(await _store(directory, cipher).load(),
          AyushSecuritySettings.defaults);
      expect(file.existsSync(), isFalse);
    });

    test('round-trips only an encrypted envelope across a restart', () async {
      const AyushSecuritySettings settings = AyushSecuritySettings(
        autoLock: AyushAutoLock.tenMinutes,
        backgroundLockGrace: AyushBackgroundLockGrace.oneMinute,
      );
      await _store(directory, cipher).save(settings);

      final String raw = file.readAsStringSync();
      expect(raw, contains(MemoryStorageEnvelope.versionKey));
      expect(raw, isNot(contains('tenMinutes')));
      expect(raw, isNot(contains('oneMinute')));
      expect(raw, isNot(contains('autoLock')));

      expect(await _store(directory, cipher).load(), settings);
    });

    test('validated legacy plaintext is migrated once, then encrypted',
        () async {
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'schema': 1,
        'autoLock': 'oneMinute',
      }));

      expect((await _store(directory, cipher).load()).autoLock,
          AyushAutoLock.oneMinute);

      final String raw = file.readAsStringSync();
      expect(raw, contains(MemoryStorageEnvelope.versionKey));
      expect(raw, isNot(contains('oneMinute')));
      expect(
        File('${file.path}.legacy.backup').existsSync(),
        isFalse,
        reason: 'migration backup is removed after a verified commit',
      );
    });

    test('invalid legacy plaintext fails closed and is never replaced',
        () async {
      const String invalid = '{"unexpected":true}';
      await file.writeAsString(invalid);

      await expectLater(
        _store(directory, cipher).load(),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(file.readAsStringSync(), invalid);
    });

    test('a different protection context cannot decrypt and changes nothing',
        () async {
      await _store(directory, cipher)
          .save(const AyushSecuritySettings(autoLock: AyushAutoLock.never));
      final String original = file.readAsStringSync();

      await expectLater(
        _store(directory, const _XorCipher(99)).load(),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(file.readAsStringSync(), original);
    });

    test('tampering with ciphertext fails closed', () async {
      await _store(directory, cipher)
          .save(const AyushSecuritySettings(autoLock: AyushAutoLock.never));
      final Map<String, dynamic> envelope =
          jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      final Uint8List payload = Uint8List.fromList(
        base64.decode(envelope[MemoryStorageEnvelope.payloadKey] as String),
      );
      payload[0] ^= 0xff;
      final String tampered = MemoryStorageEnvelope.encode(
        ciphertext: payload,
        scope: AuraProfile.ayush.storageScope,
      );
      file.writeAsStringSync(tampered);

      await expectLater(
        _store(directory, cipher).load(),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(file.readAsStringSync(), tampered);
    });

    test('unsupported encryption never falls back to plaintext', () async {
      const UnsupportedMemoryCipher unsupported = UnsupportedMemoryCipher();
      await expectLater(
        _store(directory, unsupported).load(),
        throwsA(isA<MemoryStorageException>()),
      );
      await expectLater(
        _store(directory, unsupported).save(AyushSecuritySettings.defaults),
        throwsA(isA<MemoryStorageException>()),
      );
      expect(file.existsSync(), isFalse);
    });
  });

  group('AYUSH security settings controller', () {
    late _FakeStorage storage;
    late ProfileSession session;
    late AyushSecuritySettingsController controller;

    ProfileAccess accessReader() => ProfileAccess(session);

    setUp(() {
      storage = _FakeStorage();
      session = ProfileSession.initial;
      controller = AyushSecuritySettingsController(
        store: storage,
        accessReader: accessReader,
      );
      addTearDown(controller.dispose);
    });

    void unlockAyush() {
      session = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime(2026),
        authenticated: true,
      );
    }

    test('FAMILY cannot read or write private security settings', () async {
      await expectLater(
        controller.load(),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      await expectLater(
        controller.update(AyushAutoLock.never),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      await expectLater(
        controller.updateBackgroundLockGrace(
          AyushBackgroundLockGrace.immediate,
        ),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      expect(controller.state.settings, AyushSecuritySettings.defaults);
      expect(controller.state.loaded, isFalse);
    });

    test('authenticated AYUSH can load and update the encrypted setting',
        () async {
      unlockAyush();
      storage.stored = const AyushSecuritySettings(
        autoLock: AyushAutoLock.fifteenMinutes,
      );

      await controller.load();
      expect(controller.state.loaded, isTrue);
      expect(controller.state.settings.autoLock, AyushAutoLock.fifteenMinutes);

      await controller.update(AyushAutoLock.never);
      expect(controller.state.settings.autoLock, AyushAutoLock.never);
      expect(storage.stored.autoLock, AyushAutoLock.never);
      expect(controller.state.error, isNull);

      await controller.updateBackgroundLockGrace(
        AyushBackgroundLockGrace.fifteenSeconds,
      );
      expect(
        controller.state.settings.backgroundLockGrace,
        AyushBackgroundLockGrace.fifteenSeconds,
      );
      expect(
        storage.stored.backgroundLockGrace,
        AyushBackgroundLockGrace.fifteenSeconds,
      );
      expect(controller.state.error, isNull);
    });

    test('storage failures keep the safe default and never adopt "Never"',
        () async {
      unlockAyush();
      storage.failLoad = true;
      await controller.load();
      expect(controller.state.settings.autoLock, AyushAutoLock.fiveMinutes);
      expect(controller.state.error, contains('5-minute'));
      expect(controller.state.loaded, isTrue);

      storage.failLoad = false;
      await controller.load(force: true);
      expect(controller.state.error, isNull);

      storage.failSave = true;
      await controller.update(AyushAutoLock.never);
      expect(controller.state.settings.autoLock, AyushAutoLock.fiveMinutes);
      expect(controller.state.error, isNotNull);
    });

    test('clear() wipes decrypted values on lock without a private guard',
        () async {
      unlockAyush();
      await controller.update(AyushAutoLock.never);
      expect(controller.state.settings.autoLock, AyushAutoLock.never);

      session = ProfileSession.initial;
      controller.clear();
      expect(controller.state.settings, AyushSecuritySettings.defaults);
      expect(controller.state.loaded, isFalse);
      expect(controller.state.error, isNull);
    });
  });
}
