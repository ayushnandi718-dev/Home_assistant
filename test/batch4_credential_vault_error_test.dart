import 'dart:async';
import 'dart:convert';

import 'package:aura_hub/features/ai/data/ai_credential_store.dart';
import 'package:aura_hub/features/ai/domain/ai_diagnostics.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';

class _SessionHub {
  ProfileSession _session = ProfileSession.initial;

  ProfileAccess get access => ProfileAccess(_session);
  ProfileAccessReader get reader => () => access;

  void unlockAyush() {
    _session = ProfileSession(
      profile: AuraProfile.ayush,
      startedAt: DateTime(2026),
      authenticated: true,
      generation: _session.generation + 1,
    );
  }

  void lock() {
    _session = ProfileSession(
      profile: AuraProfile.family,
      startedAt: DateTime(2026),
      generation: _session.generation + 1,
    );
  }
}

class _ControlledVault implements CredentialVault {
  final Map<String, String> secrets = <String, String>{};
  final List<String> operations = <String>[];

  int reads = 0;
  int writes = 0;
  int deletes = 0;

  Object? readError;
  Object? writeError;
  Object? deleteError;
  bool deleteResult = true;

  Completer<void>? readGate;
  Completer<void>? writeGate;
  Completer<void>? deleteGate;

  @override
  Future<String?> read({required String target}) async {
    reads++;
    operations.add('read:$target');
    final Completer<void>? gate = readGate;
    readGate = null;
    if (gate != null) await gate.future;
    if (readError != null) throw readError!;
    return secrets[target];
  }

  @override
  Future<void> write({
    required String target,
    required String secret,
    bool Function()? isCommitAllowed,
  }) async {
    writes++;
    operations.add('write:$target');
    final Completer<void>? gate = writeGate;
    writeGate = null;
    if (gate != null) await gate.future;
    if (writeError != null) throw writeError!;
    enforceCredentialCommit(
      isCommitAllowed: isCommitAllowed,
      failure: CredentialVaultFailure.writeFailure,
    );
    secrets[target] = secret;
  }

  @override
  Future<bool> delete({
    required String target,
    bool Function()? isCommitAllowed,
  }) async {
    deletes++;
    operations.add('delete:$target');
    final Completer<void>? gate = deleteGate;
    deleteGate = null;
    if (gate != null) await gate.future;
    if (deleteError != null) throw deleteError!;
    enforceCredentialCommit(
      isCommitAllowed: isCommitAllowed,
      failure: CredentialVaultFailure.deleteFailure,
    );
    if (!deleteResult) return false;
    return secrets.remove(target) != null;
  }
}

class _RecordingDiagnostics extends AiDiagnostics {
  final List<AiDiagnosticEvent> events = <AiDiagnosticEvent>[];

  @override
  void record(AiDiagnosticEvent event) => events.add(event);
}

Future<void> _waitUntil(bool Function() ready) async {
  for (int attempt = 0; attempt < 500; attempt++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Controlled vault operation never started.');
}

void main() {
  const String target = 'AURA_HUB/AI/family/groq';

  AiCredentialStore storeFor(_ControlledVault vault) =>
      AiCredentialStore(vault: vault);

  group('Batch 4 credential-vault error handling', () {
    test('missing credentials remain distinguishable from vault failures',
        () async {
      final _ControlledVault vault = _ControlledVault();
      final AiCredentialStore store = storeFor(vault);

      expect(
          await store.has(profileScope: 'family', providerId: 'groq'), isFalse);
      expect(
        await store.readSecret(profileScope: 'family', providerId: 'groq'),
        isNull,
      );

      vault.readError = StateError('SECRET-CANARY-MUST-NOT-LEAK');
      await expectLater(
        store.readSecret(profileScope: 'family', providerId: 'groq'),
        throwsA(
          isA<AiException>()
              .having(
                (AiException error) => error.kind,
                'kind',
                AiFailureKind.credentialStorage,
              )
              .having(
                (AiException error) => error.message,
                'message',
                isNot(contains('SECRET-CANARY-MUST-NOT-LEAK')),
              ),
        ),
      );
    });

    test('vault read failures use the typed credential-storage error',
        () async {
      final _ControlledVault vault = _ControlledVault()
        ..readError = const CredentialVaultException(
          CredentialVaultFailure.permissionDenied,
        );
      final AiCredentialStore store = storeFor(vault);

      await expectLater(
        store.has(profileScope: 'family', providerId: 'groq'),
        throwsA(
          isA<AiException>()
              .having(
                (AiException error) => error.kind,
                'kind',
                AiFailureKind.credentialStorage,
              )
              .having(
                (AiException error) => error.message,
                'message',
                'The device denied access to secure credential storage. '
                    'Check device permissions and try again.',
              ),
        ),
      );
    });

    test('corrupt credential data fails safely without becoming missing',
        () async {
      final _ControlledVault vault = _ControlledVault();
      vault.secrets[target] = '   ';
      final AiCredentialStore store = storeFor(vault);

      await expectLater(
        store.readSecret(profileScope: 'family', providerId: 'groq'),
        throwsA(
          isA<AiException>()
              .having(
                (AiException error) => error.kind,
                'kind',
                AiFailureKind.credentialStorage,
              )
              .having(
                (AiException error) => error.message,
                'message',
                contains('Re-enter the API key'),
              ),
        ),
      );
    });

    test('a failed save preserves the previously valid credential', () async {
      final _ControlledVault vault = _ControlledVault()
        ..secrets[target] = 'OLD-VALID-KEY'
        ..writeError = StateError('NEW-KEY-CANARY');
      final AiCredentialStore store = storeFor(vault);

      await expectLater(
        store.save(
          profileScope: 'family',
          providerId: 'groq',
          apiKey: 'NEW-KEY',
        ),
        throwsA(
          isA<AiException>()
              .having(
                (AiException error) => error.kind,
                'kind',
                AiFailureKind.credentialStorage,
              )
              .having(
                (AiException error) => error.message,
                'message',
                isNot(contains('NEW-KEY-CANARY')),
              ),
        ),
      );

      expect(vault.secrets[target], 'OLD-VALID-KEY');
      expect(vault.writes, 1);
    });

    test('a failed delete is surfaced and does not report success', () async {
      final _ControlledVault vault = _ControlledVault()
        ..secrets[target] = 'STORED-KEY'
        ..deleteResult = false;
      final AiCredentialStore store = storeFor(vault);

      await expectLater(
        store.delete(profileScope: 'family', providerId: 'groq'),
        throwsA(
          isA<AiException>()
              .having(
                (AiException error) => error.kind,
                'kind',
                AiFailureKind.credentialStorage,
              )
              .having(
                (AiException error) => error.message,
                'message',
                contains('could not be removed'),
              ),
        ),
      );

      expect(vault.secrets[target], 'STORED-KEY');
      expect(vault.deletes, 1);
    });

    test('stale AYUSH ownership prevents credential writes', () async {
      final _SessionHub hub = _SessionHub()..unlockAyush();
      final _ControlledVault vault = _ControlledVault();
      final AiCredentialStore store = storeFor(vault);
      final ProfileOperationOwner owner = ProfileOperationOwner(
        accessReader: hub.reader,
        profile: AuraProfile.ayush,
      );

      hub.lock();

      await expectLater(
        store.save(
          profileScope: AuraProfile.ayush.storageScope,
          providerId: 'groq',
          apiKey: 'PRIVATE-KEY',
          isWriteAllowed: () => owner.isCurrent,
        ),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      expect(vault.writes, 0);
      expect(vault.secrets, isEmpty);
    });

    test(
        'locking during asynchronous vault work prevents stale commit and '
        'publication', () async {
      const String ayushTarget = 'AURA_HUB/AI/ayush/groq';
      final _SessionHub hub = _SessionHub()..unlockAyush();
      final _ControlledVault vault = _ControlledVault();
      final Completer<void> readGate = Completer<void>();
      vault.readGate = readGate;
      final AiCredentialController controller = AiCredentialController(
        profile: AuraProfile.ayush,
        store: storeFor(vault),
        accessReader: hub.reader,
      );
      addTearDown(controller.dispose);

      final Future<void> refreshing = controller.refresh(providerId: 'groq');
      await _waitUntil(() => vault.reads == 1);
      vault.secrets[ayushTarget] = 'PRIVATE-KEY';
      hub.lock();
      readGate.complete();
      await refreshing;

      expect(controller.state.presence, AiCredentialPresence.unknown);
      expect(controller.state.hasError, isFalse);

      final Completer<void> writeGate = Completer<void>();
      vault.writeGate = writeGate;
      hub.unlockAyush();
      final Future<void> saving = controller.save(
        providerId: 'groq',
        apiKey: 'LATE-PRIVATE-KEY',
      );
      await _waitUntil(() => vault.writes == 1);
      hub.lock();
      writeGate.complete();
      await expectLater(saving, throwsA(isA<AuraProfileAccessDenied>()));

      // The gated write resumed only after the lock. The commit guard rejects
      // it before mutation, so the older private credential is still intact.
      expect(vault.writes, 1);
      expect(vault.secrets[ayushTarget], 'PRIVATE-KEY');
      expect(vault.secrets[ayushTarget], isNot('LATE-PRIVATE-KEY'));
      expect(controller.state.presence, AiCredentialPresence.unknown);
      expect(controller.state.hasError, isFalse);
    });

    test('a late AYUSH delete after locking preserves the private credential',
        () async {
      const String ayushTarget = 'AURA_HUB/AI/ayush/groq';
      final _SessionHub hub = _SessionHub()..unlockAyush();
      final _ControlledVault vault = _ControlledVault()
        ..secrets[ayushTarget] = 'PRIVATE-KEY';
      final AiCredentialStore store = storeFor(vault);
      final ProfileOperationOwner owner = ProfileOperationOwner(
        accessReader: hub.reader,
        profile: AuraProfile.ayush,
      );
      final Completer<void> deleteGate = Completer<void>();
      vault.deleteGate = deleteGate;

      final Future<void> deleting = store.delete(
        profileScope: AuraProfile.ayush.storageScope,
        providerId: 'groq',
        isWriteAllowed: () => owner.isCurrent,
      );
      await _waitUntil(() => vault.deletes == 1);
      hub.lock();
      deleteGate.complete();
      await expectLater(deleting, throwsA(isA<AuraProfileAccessDenied>()));

      expect(vault.secrets[ayushTarget], 'PRIVATE-KEY');
    });

    test('a stale operation after a lock never queues or starts', () async {
      final _SessionHub hub = _SessionHub()..unlockAyush();
      final _ControlledVault vault = _ControlledVault();
      final Completer<void> firstWrite = Completer<void>();
      vault.writeGate = firstWrite;
      final AiCredentialStore store = storeFor(vault);
      final ProfileOperationOwner owner = ProfileOperationOwner(
        accessReader: hub.reader,
        profile: AuraProfile.ayush,
      );

      final Future<String> first = store.save(
        profileScope: AuraProfile.ayush.storageScope,
        providerId: 'groq',
        apiKey: 'FIRST-KEY',
        isWriteAllowed: () => owner.isCurrent,
      );
      await _waitUntil(() => vault.writes == 1);
      hub.lock();
      final Future<void> staleRejected = expectLater(
        store.save(
          profileScope: AuraProfile.ayush.storageScope,
          providerId: 'groq',
          apiKey: 'QUEUED-KEY',
          isWriteAllowed: () => owner.isCurrent,
        ),
        throwsA(isA<AuraProfileAccessDenied>()),
      );

      firstWrite.complete();
      await expectLater(first, throwsA(isA<AuraProfileAccessDenied>()));
      await staleRejected;
      expect(vault.writes, 1);
      expect(vault.secrets, isEmpty);
    });

    test('the operation queue recovers after a failed write', () async {
      final _ControlledVault vault = _ControlledVault()
        ..writeError = StateError('FIRST-WRITE-FAILED');
      final AiCredentialStore store = storeFor(vault);

      await expectLater(
        store.save(
          profileScope: 'family',
          providerId: 'groq',
          apiKey: 'FIRST-KEY',
        ),
        throwsA(isA<AiException>()),
      );
      vault.writeError = null;

      expect(
        await store.save(
          profileScope: 'family',
          providerId: 'groq',
          apiKey: 'SECOND-KEY',
        ),
        target,
      );
      expect(vault.writes, 2);
      expect(vault.secrets[target], 'SECOND-KEY');
    });

    test('independent credential targets do not block each other', () async {
      final _ControlledVault vault = _ControlledVault();
      final Completer<void> groqWrite = Completer<void>();
      vault.writeGate = groqWrite;
      final AiCredentialStore store = storeFor(vault);

      final Future<String> blocked = store.save(
        profileScope: 'family',
        providerId: 'groq',
        apiKey: 'GROQ-KEY',
      );
      await _waitUntil(() => vault.writes == 1);

      final String otherTarget = await store.save(
        profileScope: 'family',
        providerId: 'openai',
        apiKey: 'OPENAI-KEY',
      );
      expect(otherTarget, 'AURA_HUB/AI/family/openai');

      groqWrite.complete();
      await blocked;
      expect(vault.operations, <String>[
        'write:$target',
        'write:AURA_HUB/AI/family/openai',
      ]);
    });

    test('profile switching prevents stale AYUSH publication', () async {
      const String ayushTarget = 'AURA_HUB/AI/ayush/groq';
      final _SessionHub hub = _SessionHub()..unlockAyush();
      final _ControlledVault vault = _ControlledVault();
      final Completer<void> writeGate = Completer<void>();
      vault.writeGate = writeGate;
      final AiCredentialController ayush = AiCredentialController(
        profile: AuraProfile.ayush,
        store: storeFor(vault),
        accessReader: hub.reader,
      );
      addTearDown(ayush.dispose);

      final Future<void> saving = ayush.save(
        providerId: 'groq',
        apiKey: 'STALE-PRIVATE-KEY',
      );
      await _waitUntil(() => vault.writes == 1);
      hub.lock();
      writeGate.complete();
      await expectLater(saving, throwsA(isA<AuraProfileAccessDenied>()));

      expect(vault.secrets[ayushTarget], isNull);
      expect(ayush.state.presence, AiCredentialPresence.unknown);
      expect(ayush.state.hasError, isFalse);

      final AiCredentialController family = AiCredentialController(
        profile: AuraProfile.family,
        store: storeFor(vault),
        accessReader: hub.reader,
      );
      addTearDown(family.dispose);
      await family.save(providerId: 'groq', apiKey: 'FAMILY-KEY');
      expect(vault.secrets['AURA_HUB/AI/family/groq'], 'FAMILY-KEY');
      expect(family.state.presence, AiCredentialPresence.present);
      expect(family.state.hasError, isFalse);
    });

    test('native error details are excluded from typed vault messages',
        () async {
      final _SessionHub hub = _SessionHub();
      final _ControlledVault vault = _ControlledVault()
        ..writeError = const CredentialVaultException(
          CredentialVaultFailure.writeFailure,
          detail: 'Bearer NATIVE-DETAIL-CANARY',
        );
      final _RecordingDiagnostics diagnostics = _RecordingDiagnostics();
      final AiCredentialController controller = AiCredentialController(
        profile: AuraProfile.family,
        store: storeFor(vault),
        accessReader: hub.reader,
        diagnostics: diagnostics,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.save(providerId: 'groq', apiKey: 'NATIVE-DETAIL-CANARY'),
        throwsA(
          isA<AiException>().having(
            (AiException error) => error.message,
            'message',
            isNot(contains('NATIVE-DETAIL-CANARY')),
          ),
        ),
      );

      expect(controller.state.failureKind, AiFailureKind.credentialStorage);
      expect(controller.state.errorMessage,
          isNot(contains('NATIVE-DETAIL-CANARY')));
      expect(controller.state.errorMessage, isNot(contains('Bearer')));
      final String serialised = jsonEncode(
        diagnostics.events
            .map((AiDiagnosticEvent event) => event.context)
            .toList(),
      );
      expect(serialised, isNot(contains('NATIVE-DETAIL-CANARY')));
      expect(serialised, isNot(contains('Bearer')));
      expect(
          diagnostics.events.single.exceptionType, 'CredentialVaultException');
    });

    test('credential errors and diagnostics never expose secrets', () async {
      final _SessionHub hub = _SessionHub();
      final _ControlledVault vault = _ControlledVault()
        ..writeError = StateError('Bearer TOP-SECRET-CANARY');
      final _RecordingDiagnostics diagnostics = _RecordingDiagnostics();
      final AiCredentialController controller = AiCredentialController(
        profile: AuraProfile.family,
        store: storeFor(vault),
        accessReader: hub.reader,
        diagnostics: diagnostics,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.save(providerId: 'groq', apiKey: 'TOP-SECRET-CANARY'),
        throwsA(isA<AiException>()),
      );

      expect(controller.state.failureKind, AiFailureKind.credentialStorage);
      expect(controller.state.errorMessage, isNotNull);
      expect(
          controller.state.errorMessage, isNot(contains('TOP-SECRET-CANARY')));
      expect(controller.state.errorMessage, isNot(contains('Bearer')));

      final String serialised = jsonEncode(
        diagnostics.events
            .map((AiDiagnosticEvent event) => event.context)
            .toList(),
      );
      expect(serialised, isNot(contains('TOP-SECRET-CANARY')));
      expect(serialised, isNot(contains('Bearer')));
      expect(diagnostics.events, hasLength(1));
      expect(diagnostics.events.single.failureKind,
          AiFailureKind.credentialStorage);
      expect(diagnostics.events.single.exceptionType, 'StateError');
    });

    test('successful save, read and delete behaviour remains intact', () async {
      final _ControlledVault vault = _ControlledVault();
      final AiCredentialStore store = storeFor(vault);

      expect(
          await store.has(profileScope: 'family', providerId: 'groq'), isFalse);
      final String handle = await store.save(
        profileScope: 'family',
        providerId: 'groq',
        apiKey: 'VALID-KEY',
      );
      expect(handle, target);
      expect(handle, isNot(contains('VALID-KEY')));
      expect(
        await store.readSecret(profileScope: 'family', providerId: 'groq'),
        'VALID-KEY',
      );
      await store.delete(profileScope: 'family', providerId: 'groq');
      expect(
          await store.has(profileScope: 'family', providerId: 'groq'), isFalse);
    });

    test('concurrent saves are serialised for one credential target', () async {
      final _ControlledVault vault = _ControlledVault();
      final Completer<void> firstWrite = Completer<void>();
      vault.writeGate = firstWrite;
      final AiCredentialStore store = storeFor(vault);

      final Future<String> first = store.save(
        profileScope: 'family',
        providerId: 'groq',
        apiKey: 'FIRST-KEY',
      );
      await _waitUntil(() => vault.writes == 1);

      final Future<String> second = store.save(
        profileScope: 'family',
        providerId: 'groq',
        apiKey: 'SECOND-KEY',
      );
      await Future<void>.delayed(Duration.zero);
      expect(vault.writes, 1);

      firstWrite.complete();
      await Future.wait(<Future<void>>[first, second]);

      expect(vault.writes, 2);
      expect(vault.secrets[target], 'SECOND-KEY');
      expect(vault.operations, <String>['write:$target', 'write:$target']);
    });

    test('unsupported vault writes keep the existing fail-closed exception',
        () async {
      final AiCredentialStore store = AiCredentialStore.unavailable();

      await expectLater(
        store.save(
          profileScope: 'family',
          providerId: 'groq',
          apiKey: 'MUST-NOT-BE-STORED',
        ),
        throwsA(isA<CredentialStorageUnavailable>()),
      );
    });
  });
}
