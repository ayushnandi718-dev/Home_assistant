import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_hub/features/ai/data/ai_conversation_storage_envelope.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_store.dart';
import 'package:aura_hub/features/ai/data/encrypted_ai_conversation_store.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_query.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/windows_dpapi_memory_cipher.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _privateText = 'my private AYUSH transcript secret';
const String _familyText = 'shared household transcript';

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

Directory _tempDir() => Directory.systemTemp.createTempSync('aura_phase5b_');

File _file(Directory directory, String name) =>
    File('${directory.path}${Platform.pathSeparator}$name');

ProfileAccessReader _reader(
  AuraProfile profile, {
  bool authenticated = true,
}) =>
    () => ProfileAccess(
          ProfileSession(
            profile: profile,
            startedAt: DateTime(2026, 1, 1),
            authenticated: authenticated,
          ),
        );

AiConversation _privateConversation({
  String id = 'ayush-1',
  String content = _privateText,
}) {
  final DateTime stamp = DateTime(2026, 1, 10, 9);
  return AiConversation(
    id: id,
    profileScope: 'ayush',
    createdAt: stamp,
    updatedAt: stamp,
    messages: <AiMessage>[
      AiMessage(
        id: '$id-m1',
        role: AiMessageRole.user,
        content: content,
        timestamp: stamp,
      ),
    ],
  );
}

Map<String, dynamic> _legacyJson(AiConversation conversation) {
  final Map<String, dynamic> json = Map<String, dynamic>.from(
    conversation.toJson(),
  )..remove('profileScope');
  return json;
}

Future<void> _waitUntil(bool Function() ready, String message) async {
  for (int attempt = 0; attempt < 400; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail(message);
}

class _Harness {
  _Harness({int cipherKey = 7}) {
    directory = _tempDir();
    cipher = _XorCipher(cipherKey);
    store = EncryptedAiConversationStore(
      directory: directory,
      profile: AuraProfile.ayush,
      cipher: cipher,
    );
    familyStore = AiConversationStore(
      directory: directory,
      profile: AuraProfile.family,
    );
  }

  late final Directory directory;
  late final _XorCipher cipher;
  late final EncryptedAiConversationStore store;
  late final AiConversationStore familyStore;

  File get secureFile =>
      _file(directory, AiConversationStorageEnvelope.fileName);
  File get legacyFile => _file(directory, 'ai_conversations_ayush.json');
  File get familyFile => _file(directory, 'ai_conversations_family.json');

  EncryptedAiConversationStore storeWithCipher(
    MemoryCipher replacement, {
    Future<void> Function()? beforeMigrationCommit,
  }) =>
      EncryptedAiConversationStore(
        directory: directory,
        profile: AuraProfile.ayush,
        cipher: replacement,
        beforeMigrationCommit: beforeMigrationCommit,
      );

  Future<void> dispose() async {
    await Future<void>.delayed(const Duration(milliseconds: 30));
    for (int attempt = 0; attempt < 10; attempt++) {
      if (!directory.existsSync()) return;
      try {
        directory.deleteSync(recursive: true);
        return;
      } on PathAccessException {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    }
  }
}

void main() {
  group('Phase 5B encrypted AYUSH conversation storage', () {
    test(
        'real Windows DPAPI round-trips conversation entropy and detects tamper',
        () async {
      if (!Platform.isWindows) return;
      final WindowsDpapiMemoryCipher cipher = WindowsDpapiMemoryCipher(
        entropy: AiConversationStorageEnvelope.dpapiEntropy,
      );
      final List<int> plaintext = utf8.encode(_privateText);
      final Uint8List ciphertext = await cipher.encrypt(plaintext);
      expect(ciphertext, isNot(equals(plaintext)));
      expect(utf8.decode(await cipher.decrypt(ciphertext)), _privateText);

      final Uint8List tampered = Uint8List.fromList(ciphertext);
      tampered[tampered.length - 2] ^= 0xff;
      await expectLater(
        cipher.decrypt(tampered),
        throwsA(isA<MemoryStorageException>()),
      );

      final WindowsDpapiMemoryCipher memoryContext = WindowsDpapiMemoryCipher(
        entropy: 'aura-hub-memory-v1',
      );
      await expectLater(
        memoryContext.decrypt(ciphertext),
        throwsA(isA<MemoryStorageException>()),
      );
    });

    test('conversation entropy differs from AYUSH memory entropy', () {
      expect(
        AiConversationStorageEnvelope.dpapiEntropy,
        isNot(WindowsDpapiMemoryCipher.defaultEntropy),
      );
      expect(
        AiConversationStorageEnvelope.purpose,
        isNot('ayush'),
      );
    });

    test('writes only an encrypted envelope and survives a store restart',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      await harness.store.write(<AiConversation>[_privateConversation()]);

      final String raw = harness.secureFile.readAsStringSync();
      expect(raw, contains(AiConversationStorageEnvelope.versionKey));
      expect(raw, contains(AiConversationStorageEnvelope.purposeKey));
      expect(raw, contains(AiConversationStorageEnvelope.payloadKey));
      expect(raw, isNot(contains(_privateText)));

      final EncryptedAiConversationStore restarted =
          EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      );
      final AiConversationLoadResult result = await restarted.read();
      expect(result.outcome, AiConversationLoadOutcome.ready);
      expect(result.conversations.single.id, 'ayush-1');
      expect(result.conversations.single.list().single.content, _privateText);
      expect(
        result.conversations.single.list().single.conversationId,
        'ayush-1',
      );
    });

    test('no plaintext transcript exists in any file, temp or backup',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);

      await harness.store.write(<AiConversation>[_privateConversation()]);
      await harness.store.write(<AiConversation>[
        _privateConversation(id: 'ayush-2', content: 'second private line'),
      ]);

      expect(harness.legacyFile.existsSync(), isFalse);
      for (final FileSystemEntity entity in harness.directory.listSync()) {
        if (entity is! File) continue;
        expect(entity.readAsStringSync(), isNot(contains(_privateText)));
        expect(
            entity.readAsStringSync(), isNot(contains('second private line')));
      }
      expect(
        _file(harness.directory,
                '${AiConversationStorageEnvelope.fileName}.secure.tmp')
            .existsSync(),
        isFalse,
      );
      expect(
        _file(harness.directory,
                '${AiConversationStorageEnvelope.fileName}.secure.backup')
            .existsSync(),
        isFalse,
      );
    });

    test('missing encrypted file starts with an empty history', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      final AiConversationLoadResult result = await harness.store.read();
      expect(result.outcome, AiConversationLoadOutcome.ready);
      expect(result.conversations, isEmpty);
      expect(harness.secureFile.existsSync(), isFalse);
    });

    test('validates and migrates legacy plaintext, then removes it', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      await harness.legacyFile.writeAsString(
        jsonEncode(<Map<String, dynamic>>[
          _legacyJson(_privateConversation()),
        ]),
      );

      final AiConversationLoadResult result = await harness.store.read();
      expect(result.outcome, AiConversationLoadOutcome.ready);
      expect(result.conversations.single.profileScope, 'ayush');
      expect(result.conversations.single.list().single.content, _privateText);
      expect(harness.legacyFile.existsSync(), isFalse);
      expect(harness.secureFile.existsSync(), isTrue);
      expect(
          harness.secureFile.readAsStringSync(), isNot(contains(_privateText)));
    });

    test('migration is idempotent across restarts and repeated legacy files',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      final String legacy = jsonEncode(<Map<String, dynamic>>[
        _legacyJson(_privateConversation()),
      ]);
      await harness.legacyFile.writeAsString(legacy);

      expect((await harness.store.read()).conversations, hasLength(1));
      final EncryptedAiConversationStore restarted =
          EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      );
      expect((await restarted.read()).conversations, hasLength(1));

      // A stale legacy copy appearing later must not duplicate or replace the
      // already committed encrypted history.
      await harness.legacyFile.writeAsString(legacy);
      final AiConversationLoadResult again = await restarted.read();
      expect(again.outcome, AiConversationLoadOutcome.ready);
      expect(again.conversations, hasLength(1));
      expect(harness.legacyFile.existsSync(), isFalse);
    });

    test('interrupted migration preserves legacy plaintext and retries',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      final String legacy = jsonEncode(<Map<String, dynamic>>[
        _legacyJson(_privateConversation()),
      ]);
      await harness.legacyFile.writeAsString(legacy);

      final EncryptedAiConversationStore interrupted =
          EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
        beforeMigrationCommit: () async {
          throw StateError('simulated interruption');
        },
      );
      final AiConversationLoadResult result = await interrupted.read();
      expect(result.outcome, AiConversationLoadOutcome.failed);
      expect(result.detail, isNot(contains(_privateText)));
      expect(harness.legacyFile.readAsStringSync(), legacy);
      expect(harness.secureFile.existsSync(), isFalse);

      final AiConversationLoadResult retry = await EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      ).read();
      expect(retry.outcome, AiConversationLoadOutcome.ready);
      expect(retry.conversations.single.list().single.content, _privateText);
      expect(harness.legacyFile.existsSync(), isFalse);
    });

    test(
        'malformed, cross-profile, duplicate and unsupported legacy data fails closed',
        () async {
      final Map<String, dynamic> base = _legacyJson(_privateConversation());
      final Map<String, dynamic> duplicateMessage = Map<String, dynamic>.from(
        (base['messages'] as List<dynamic>).single as Map<String, dynamic>,
      )..['id'] = 'duplicate-message-id';
      final Map<String, dynamic> duplicateMessages = Map<String, dynamic>.from(
        base,
      )..['messages'] = <dynamic>[duplicateMessage, duplicateMessage];

      final List<String> invalidPayloads = <String>[
        '{not json',
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            ...base,
            'profileScope': 'family',
          },
        ]),
        jsonEncode(<Map<String, dynamic>>[
          base,
          base,
        ]),
        jsonEncode(<String, dynamic>{
          'schemaVersion': 99,
          'profile': 'ayush',
          'conversations': <dynamic>[],
        }),
        jsonEncode(<String, dynamic>{
          'conversations': <dynamic>[base],
        }),
        jsonEncode(<String, dynamic>{
          'schemaVersion': '2',
          'conversations': <dynamic>[base],
        }),
        jsonEncode(<Map<String, dynamic>>[
          <String, dynamic>{
            ...base,
            'profileScope': 'ayush',
            'scope': 'family',
          },
        ]),
        jsonEncode(<Map<String, dynamic>>[duplicateMessages]),
      ];

      for (final String payload in invalidPayloads) {
        final _Harness harness = _Harness();
        addTearDown(harness.dispose);
        await harness.legacyFile.writeAsString(payload);
        final AiConversationLoadResult result = await harness.store.read();
        expect(result.outcome, AiConversationLoadOutcome.failed);
        expect(result.detail, isNot(contains(_privateText)));
        expect(harness.legacyFile.readAsStringSync(), payload);
        expect(harness.secureFile.existsSync(), isFalse);
      }
    });

    test('DPAPI unavailable fails closed without plaintext fallback', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      final EncryptedAiConversationStore unsupported =
          EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: const UnsupportedMemoryCipher(),
      );

      final AiConversationLoadResult result = await unsupported.read();
      expect(result.outcome, AiConversationLoadOutcome.failed);
      expect(result.detail, contains('unavailable'));
      await expectLater(
        unsupported.write(<AiConversation>[_privateConversation()]),
        throwsA(isA<AiConversationStorageException>()),
      );
      expect(harness.secureFile.existsSync(), isFalse);
      expect(harness.legacyFile.existsSync(), isFalse);

      await harness.store.write(<AiConversation>[_privateConversation()]);
      final String encrypted = harness.secureFile.readAsStringSync();
      expect(
          (await unsupported.read()).outcome, AiConversationLoadOutcome.failed);
      expect(harness.secureFile.readAsStringSync(), encrypted);
    });

    test('tampered ciphertext is rejected and blocks later writes', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      await harness.store.write(<AiConversation>[_privateConversation()]);

      final Map<String, dynamic> envelope =
          jsonDecode(harness.secureFile.readAsStringSync())
              as Map<String, dynamic>;
      final Uint8List payload = Uint8List.fromList(
        base64.decode(
            envelope[AiConversationStorageEnvelope.payloadKey] as String),
      );
      payload[0] ^= 0xff;
      final String tampered = AiConversationStorageEnvelope.encode(
        ciphertext: payload,
        scope: AuraProfile.ayush.storageScope,
      );
      await harness.secureFile.writeAsString(tampered);

      final AiConversationLoadResult result = await harness.store.read();
      expect(result.outcome, AiConversationLoadOutcome.failed);
      expect(result.detail, contains('could not be decrypted'));
      expect(result.detail, isNot(contains(_privateText)));
      expect(harness.secureFile.readAsStringSync(), tampered);

      await expectLater(
        harness.store.write(<AiConversation>[
          _privateConversation(id: 'overwrite-attempt'),
        ]),
        throwsA(isA<AiConversationStorageException>()),
      );
      expect(harness.secureFile.readAsStringSync(), tampered);
    });

    test('wrong protection context fails closed without replacing the file',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      await harness.store.write(<AiConversation>[_privateConversation()]);
      final String encrypted = harness.secureFile.readAsStringSync();

      final EncryptedAiConversationStore wrongContext =
          EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: _XorCipher(99),
      );
      final AiConversationLoadResult result = await wrongContext.read();
      expect(result.outcome, AiConversationLoadOutcome.failed);
      expect(result.detail, contains('could not be decrypted'));
      await expectLater(
        wrongContext.write(<AiConversation>[
          _privateConversation(id: 'wrong-context-write'),
        ]),
        throwsA(isA<AiConversationStorageException>()),
      );
      expect(harness.secureFile.readAsStringSync(), encrypted);
    });

    test('invalid envelope fields and invalid decrypted JSON fail closed',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      await harness.store.write(<AiConversation>[_privateConversation()]);
      final Map<String, dynamic> valid =
          jsonDecode(harness.secureFile.readAsStringSync())
              as Map<String, dynamic>;

      final List<Map<String, dynamic>> invalidEnvelopes =
          <Map<String, dynamic>>[
        <String, dynamic>{
          ...valid,
          AiConversationStorageEnvelope.versionKey: 999,
        },
        <String, dynamic>{
          ...valid,
          AiConversationStorageEnvelope.cipherKey: 'plaintext',
        },
        <String, dynamic>{
          ...valid,
          AiConversationStorageEnvelope.scopeKey: 'family',
        },
        <String, dynamic>{
          ...valid,
          AiConversationStorageEnvelope.purposeKey: 'ayush-memory',
        },
        <String, dynamic>{
          ...valid,
          AiConversationStorageEnvelope.payloadKey: '',
        },
      ];

      for (final Map<String, dynamic> bad in invalidEnvelopes) {
        final String raw = jsonEncode(bad);
        await harness.secureFile.writeAsString(raw);
        final EncryptedAiConversationStore store = EncryptedAiConversationStore(
          directory: harness.directory,
          profile: AuraProfile.ayush,
          cipher: harness.cipher,
        );
        final AiConversationLoadResult result = await store.read();
        expect(result.outcome, AiConversationLoadOutcome.failed);
        expect(result.detail, isNot(contains(_privateText)));
        expect(harness.secureFile.readAsStringSync(), raw);
      }

      final String invalidJson = AiConversationStorageEnvelope.encode(
        ciphertext: await harness.cipher.encrypt(utf8.encode('{not json')),
        scope: AuraProfile.ayush.storageScope,
      );
      await harness.secureFile.writeAsString(invalidJson);
      final AiConversationLoadResult badJson =
          await EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      ).read();
      expect(badJson.outcome, AiConversationLoadOutcome.failed);
      expect(badJson.detail, isNot(contains(_privateText)));
      expect(harness.secureFile.readAsStringSync(), invalidJson);

      final Map<String, dynamic> crossProfileRecord = _privateConversation()
          .toJson()
        ..['profileScope'] = AuraProfile.family.storageScope;
      final String crossProfilePayload = AiConversationStorageEnvelope.encode(
        ciphertext: await harness.cipher.encrypt(
          utf8.encode(
            jsonEncode(<String, dynamic>{
              'schema': 1,
              'conversations': <dynamic>[crossProfileRecord],
            }),
          ),
        ),
        scope: AuraProfile.ayush.storageScope,
      );
      await harness.secureFile.writeAsString(crossProfilePayload);
      final AiConversationLoadResult badSchema =
          await EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      ).read();
      expect(badSchema.outcome, AiConversationLoadOutcome.failed);
      expect(badSchema.detail, isNot(contains(_privateText)));
      expect(harness.secureFile.readAsStringSync(), crossProfilePayload);
    });

    test('encrypted temp is recovered after an interrupted commit', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      await harness.store.write(<AiConversation>[_privateConversation()]);

      final File temp = _file(
        harness.directory,
        '${AiConversationStorageEnvelope.fileName}.secure.tmp',
      );
      final String committed = harness.secureFile.readAsStringSync();
      await temp.writeAsString(committed);
      await harness.secureFile.delete();

      final AiConversationLoadResult result =
          await EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
      ).read();
      expect(result.outcome, AiConversationLoadOutcome.ready);
      expect(result.conversations.single.list().single.content, _privateText);
      expect(harness.secureFile.existsSync(), isTrue);
      expect(temp.existsSync(), isFalse);
    });

    test('repository enforces access and never writes while locked', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      final ProfileBoundAiConversationRepository locked =
          ProfileBoundAiConversationRepository(
        profile: AuraProfile.ayush,
        storage: harness.store,
        accessReader: _reader(AuraProfile.ayush, authenticated: false),
      );
      expect(
        () => locked.load(),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      expect(
        () => locked.save(<AiConversation>[_privateConversation()]),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      expect(harness.secureFile.existsSync(), isFalse);
    });

    test('lock clears decrypted state but preserves encrypted history',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      bool authenticated = true;
      ProfileAccess reader() => ProfileAccess(
            ProfileSession(
              profile: authenticated ? AuraProfile.ayush : AuraProfile.family,
              startedAt: DateTime(2026, 1, 1),
              authenticated: authenticated,
            ),
          );
      final AiConversationLibraryController library =
          AiConversationLibraryController(
        profile: AuraProfile.ayush,
        storage: harness.store,
        accessReader: reader,
        now: () => DateTime(2026, 1, 10, 9),
      );
      await library.load();
      addTearDown(library.dispose);

      final String id = library.create();
      library.appendMessage(
        id,
        AiMessage(
          role: AiMessageRole.user,
          content: _privateText,
          timestamp: DateTime(2026, 1, 10, 9),
        ),
      );
      for (int attempt = 0; attempt < 200; attempt++) {
        final AiConversationLoadResult persisted = await harness.store.read();
        if (persisted.conversations.isNotEmpty &&
            persisted.conversations.single.messageCount == 1) {
          break;
        }
        if (attempt == 199) fail('AYUSH message was not encrypted to disk.');
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(library.state.single.list().single.content, _privateText);

      authenticated = false;
      library.discardForLock();
      expect(library.state, isEmpty);
      expect(library.recovery.phase, AiConversationLoadPhase.idle);
      expect(harness.secureFile.existsSync(), isTrue);
      expect(
        () => ProfileBoundAiConversationRepository(
          profile: AuraProfile.ayush,
          storage: harness.store,
          accessReader: reader,
        ).load(),
        throwsA(isA<AuraProfileAccessDenied>()),
      );

      authenticated = true;
      await library.load();
      expect(library.state.single.list().single.content, _privateText);
    });

    test('a write pending during lock cannot update the encrypted file',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      final Completer<void> gate = Completer<void>();
      bool reachedGate = false;
      final EncryptedAiConversationStore gated = EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
        beforeWriteCommit: () {
          reachedGate = true;
          return gate.future;
        },
      );
      bool authenticated = true;
      final AiConversationLibraryController library =
          AiConversationLibraryController(
        profile: AuraProfile.ayush,
        storage: gated,
        accessReader: () => ProfileAccess(
          ProfileSession(
            profile: authenticated ? AuraProfile.ayush : AuraProfile.family,
            startedAt: DateTime(2026, 1, 1),
            authenticated: authenticated,
          ),
        ),
      );
      await library.load();
      addTearDown(library.dispose);

      library.create();
      await _waitUntil(
          () => reachedGate, 'Write did not reach the commit gate.');
      authenticated = false;
      library.discardForLock();
      gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      expect(harness.secureFile.existsSync(), isFalse);
      expect(library.state, isEmpty);
    });

    test('reads are serialized behind writes and see the committed payload',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      final Completer<void> gate = Completer<void>();
      bool reachedGate = false;
      final EncryptedAiConversationStore gated = EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
        beforeWriteCommit: () {
          reachedGate = true;
          return gate.future;
        },
      );

      final Future<void> pendingWrite =
          gated.write(<AiConversation>[_privateConversation()]);
      await _waitUntil(
        () => reachedGate,
        'Write did not reach the commit gate.',
      );

      bool readCompleted = false;
      final Future<AiConversationLoadResult> pendingRead = gated.read()
        ..whenComplete(() => readCompleted = true);
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(readCompleted, isFalse);

      gate.complete();
      await pendingWrite;
      final AiConversationLoadResult result = await pendingRead;
      expect(result.outcome, AiConversationLoadOutcome.ready);
      expect(result.conversations.single.list().single.content, _privateText);
      expect(
        _file(
          harness.directory,
          '${AiConversationStorageEnvelope.fileName}.secure.tmp',
        ).existsSync(),
        isFalse,
      );
    });

    test('a load pending during lock is invalidated without leaking content',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      final Completer<void> gate = Completer<void>();
      bool reachedGate = false;
      final EncryptedAiConversationStore gated = EncryptedAiConversationStore(
        directory: harness.directory,
        profile: AuraProfile.ayush,
        cipher: harness.cipher,
        beforeReadCommit: () {
          reachedGate = true;
          return gate.future;
        },
      );
      await gated.write(<AiConversation>[_privateConversation()]);

      final Future<AiConversationLoadResult> pendingRead = gated.read();
      await _waitUntil(
        () => reachedGate,
        'Read did not reach the commit gate.',
      );
      await gated.clear();
      gate.complete();

      final AiConversationLoadResult result = await pendingRead;
      expect(result.outcome, AiConversationLoadOutcome.failed);
      expect(result.detail, contains('workspace changed'));
      expect(result.detail, isNot(contains(_privateText)));
      expect(harness.secureFile.existsSync(), isTrue);
    });

    test('FAMILY storage stays plaintext and profile search stays isolated',
        () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      await harness.store.write(<AiConversation>[_privateConversation()]);
      await harness.familyStore.write(<AiConversation>[
        AiConversation(
          id: 'family-1',
          profileScope: 'family',
          messages: <AiMessage>[
            AiMessage(
              role: AiMessageRole.user,
              content: _familyText,
              timestamp: DateTime(2026, 1, 2),
            ),
          ],
        ),
      ]);

      expect(harness.familyFile.readAsStringSync(), contains(_familyText));
      expect(
          harness.secureFile.readAsStringSync(), isNot(contains(_privateText)));
      expect(
          harness.familyFile.readAsStringSync(), isNot(contains(_privateText)));

      final List<AiConversation> private =
          (await harness.store.read()).conversations;
      final List<AiConversation> family =
          (await harness.familyStore.read()).conversations;
      expect(searchAiConversations(private, query: 'household'), isEmpty);
      expect(searchAiConversations(family, query: 'AYUSH transcript'), isEmpty);
      expect(searchAiConversations(private, query: 'AYUSH transcript'),
          hasLength(1));
      expect(searchAiConversations(family, query: 'household'), hasLength(1));
    });

    test('error messages never expose transcript content', () async {
      final _Harness harness = _Harness();
      addTearDown(harness.dispose);
      await harness.legacyFile.writeAsString('{invalid');
      final AiConversationLoadResult result = await harness.store.read();
      expect(result.outcome, AiConversationLoadOutcome.failed);
      expect(result.detail, isNotNull);
      expect(result.detail, isNot(contains(_privateText)));

      final String unsupported = AiConversationStorageMessages.unsupported;
      final String decryption = AiConversationStorageMessages.decryption;
      for (final String message in <String>[
        unsupported,
        decryption,
        AiConversationStorageMessages.unreadable,
        AiConversationStorageMessages.migration,
        AiConversationStorageMessages.write,
        AiConversationStorageMessages.locked,
        AiConversationStorageMessages.stale,
      ]) {
        expect(message, isNot(contains(_privateText)));
        expect(message, isNot(contains('Exception')));
      }
    });

    test('providers select encrypted AYUSH and plaintext FAMILY storage', () {
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          ayushConversationCipherProvider.overrideWithValue(_XorCipher(5)),
          profileAccessProvider.overrideWithValue(
            ProfileAccess(
              ProfileSession(
                profile: AuraProfile.ayush,
                startedAt: DateTime(2026),
                authenticated: true,
              ),
            ),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(
        container.read(aiConversationStorageForProvider(AuraProfile.ayush)),
        isA<EncryptedAiConversationStore>(),
      );
      expect(
        container.read(aiConversationStorageForProvider(AuraProfile.family)),
        isA<AiConversationStore>(),
      );
    });
  });
}
