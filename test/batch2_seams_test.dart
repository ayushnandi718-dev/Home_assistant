import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aura_hub/core/platform/atomic_file_writer_stub.dart'
    as web_atomic;
import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/features/integrations/data/windows_credential_vault_io.dart'
    as vault_io;
import 'package:aura_hub/features/memory/data/native_memory_guard.dart';
import 'package:aura_hub/features/memory/data/windows_dpapi_memory_cipher_io.dart'
    as dpapi_io;
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ffi/ffi.dart';

class _MemoryPinFile implements ProfilePinFile {
  String contents = '';
  final List<String> calls = <String>[];

  @override
  Future<bool> exists() async => contents.isNotEmpty;

  @override
  Future<String> readAsString() async => contents;

  @override
  Future<void> writeAsString(String value, {required bool flush}) async {
    calls.add('write:$flush');
    contents = value;
  }

  @override
  Future<void> replaceWith(
    String value, {
    bool Function()? isCommitAllowed,
  }) async {
    if (isCommitAllowed != null && !isCommitAllowed()) {
      throw const AuraProfileAccessDenied(AuraProfile.ayush);
    }
    calls.add('replace');
    contents = value;
  }

  @override
  Future<void> createParent() async {
    calls.add('createParent');
  }

  @override
  Future<void> delete() async {
    calls.add('delete');
    contents = '';
  }
}

void main() {
  group('Batch 2 seams', () {
    test('native memory guard zeroes a buffer before invoking its allocator',
        () async {
      const FillNativeMemoryGuard guard = FillNativeMemoryGuard();
      final Pointer<Uint8> pointer = calloc<Uint8>(4);
      addTearDown(() => calloc.free(pointer));

      final Uint8List view = pointer.asTypedList(4);
      view.setAll(0, <int>[1, 2, 3, 4]);
      final List<String> order = <String>[];

      guard.zeroThenFree(view, pointer.cast<Void>(), (Pointer<Void> released) {
        expect(released.address, pointer.address);
        order.add('free');
      });
      order.insert(0, view.every((int byte) => byte == 0) ? 'zero' : 'dirty');

      expect(order, <String>['zero', 'free']);
    });

    test('DPAPI output is zeroed before LocalFree receives its own pointer',
        () async {
      const FillNativeMemoryGuard guard = FillNativeMemoryGuard();
      final Pointer<Uint8> buffer = calloc<Uint8>(4);
      addTearDown(() => calloc.free(buffer));
      final Uint8List view = buffer.asTypedList(4);
      view.setAll(0, <int>[9, 8, 7, 6]);
      final List<String> order = <String>[];

      dpapi_io.scrubDpapiLocalAllocOutput(
        guard: guard,
        buffer: buffer,
        length: 4,
        localFree: (Pointer<Void> released) {
          expect(released.address, buffer.address);
          order.add(view.every((int byte) => byte == 0) ? 'zero' : 'dirty');
          order.add('localFree');
        },
      );

      expect(order, <String>['zero', 'localFree']);
    });

    test('vault heap blob is zeroed before HeapFree receives its own pointer',
        () async {
      const FillNativeMemoryGuard guard = FillNativeMemoryGuard();
      final Pointer<Uint8> blob = calloc<Uint8>(6);
      addTearDown(() => calloc.free(blob));
      final Uint8List view = blob.asTypedList(6);
      view.setAll(0, <int>[1, 2, 3, 4, 5, 6]);
      final List<String> order = <String>[];

      vault_io.scrubHeapSecretBlob(
        guard: guard,
        blob: blob,
        byteLength: 6,
        heapFree: (Pointer<Void> released) {
          expect(released.address, blob.address);
          order.add(view.every((int byte) => byte == 0) ? 'zero' : 'dirty');
          order.add('heapFree');
        },
      );

      expect(order, <String>['zero', 'heapFree']);
    });

    test('CredRead graph is scrubbed and freed with CredFree only', () async {
      const FillNativeMemoryGuard guard = FillNativeMemoryGuard();
      final Pointer<Void> credential = calloc<Uint8>(8).cast<Void>();
      final Pointer<Uint8> blob = calloc<Uint8>(4);
      addTearDown(() => calloc.free(credential));
      addTearDown(() => calloc.free(blob));
      final Uint8List view = blob.asTypedList(4);
      view.setAll(0, <int>[11, 22, 33, 44]);
      final List<String> order = <String>[];

      vault_io.scrubCredReadGraph(
        guard: guard,
        credential: credential,
        blob: blob,
        byteLength: 4,
        credFree: (Pointer<Void> released) {
          expect(released.address, credential.address);
          expect(released.address, isNot(blob.address));
          order.add(view.every((int byte) => byte == 0) ? 'zero' : 'dirty');
          order.add('credFree');
        },
      );

      expect(order, <String>['zero', 'credFree']);
    });

    test('telemetry config carries an in-memory auth token through copyWith',
        () {
      const TelemetryApiConfig config = TelemetryApiConfig(authToken: 'raw');
      expect(config.authToken, 'raw');
      expect(config.copyWith(port: 9000).authToken, 'raw');
      expect(
        config.copyWith(authToken: 'rotated').authToken,
        'rotated',
      );
      expect(config.toString(), isNot(contains('raw')));
    });

    test('telemetry tokens are URL-safe, distinct per launch and opaque', () {
      final String first = generateTelemetryApiAuthToken(
        random: math.Random(7),
      );
      final String second = generateTelemetryApiAuthToken(
        random: math.Random(8),
      );

      expect(first, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
      expect(first, isNot(second));
      expect(second, matches(RegExp(r'^[A-Za-z0-9_-]{43}$')));
    });

    test('PIN store uses the injected file seam without touching a real file',
        () async {
      final _MemoryPinFile file = _MemoryPinFile();
      final ProfilePinStore store = ProfilePinStore(
        iterations: 1000,
        file: file,
      );

      await store.setPin('1234');

      final Object? decoded = jsonDecode(file.contents);
      expect(decoded, isA<Map<String, dynamic>>());
      final Map<String, dynamic> verifier = decoded as Map<String, dynamic>;
      expect(verifier['version'], 2);
      expect(verifier['kdf'], 'pbkdf2-hmac-sha256');
      expect(verifier['iterations'], 1000);
      expect(verifier['salt'], isNotEmpty);
      expect(verifier['hash'], isNotEmpty);
      expect(await store.hasPin(), isTrue);
      expect(await store.verify('1234'), isTrue);
      expect(file.calls, contains('replace'));
      // Atomic replacement owns parent creation; the seam sees only the
      // final replace operation.
      expect(file.calls, isNot(contains('write:true')));
    });

    test('PIN verifier replacement leaves no temporary file', () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('aura_atomic_pin_');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final ProfilePinStore store = ProfilePinStore(
        directory: directory,
        iterations: 1000,
      );

      await store.setPin('2468');
      await store.setPin('1357');

      final List<String> names = (await directory.list().toList())
          .map((FileSystemEntity entity) => entity.uri.pathSegments.last)
          .toList(growable: false);
      expect(names, <String>['profile_pin.json']);
      expect(await store.verify('1357'), isTrue);
    });

    test('web atomic write refuses a stale guard without replacing the file',
        () async {
      final Directory directory =
          await Directory.systemTemp.createTemp('aura_web_atomic_');
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      final File file = File('${directory.path}${Platform.pathSeparator}pin');
      await file.writeAsString('original', flush: true);

      await expectLater(
        web_atomic.atomicWriteString(file, 'rejected', isCommitAllowed: () {
          throw const AuraProfileAccessDenied(AuraProfile.ayush);
        }),
        throwsA(isA<AuraProfileAccessDenied>()),
      );
      expect(await file.readAsString(), 'original');

      await web_atomic.atomicWriteString(
        file,
        'committed',
        isCommitAllowed: () => true,
      );
      expect(await file.readAsString(), 'committed');
    });

    test('corrupt lockout state becomes a fixed temporary recovery lock',
        () async {
      final _MemoryPinFile file = _MemoryPinFile();
      final DateTime now = DateTime(2026, 1, 2, 3, 4);
      final ProfilePinLockoutStore store = ProfilePinLockoutStore(
        file: file,
        now: () => now,
      );

      await store.save(failedAttempts: 2, lockedUntil: null);
      final ProfilePinLockoutState saved = await store.load();
      expect(saved.failedAttempts, 2);
      expect(saved.lockedUntil, isNull);
      expect(saved.corrupt, isFalse);

      file.contents = '{broken';
      final ProfilePinLockoutState recovered = await store.load();
      expect(recovered.corrupt, isTrue);
      expect(recovered.failedAttempts, 5);
      expect(
        recovered.lockedUntil,
        now.add(ProfilePinLockoutStore.corruptStateLockout),
      );
      // The normalized file no longer contains the corrupt payload.
      expect(
        await ProfilePinLockoutStore(file: file, now: () => now).load(),
        isA<ProfilePinLockoutState>().having(
            (ProfilePinLockoutState state) => state.corrupt,
            'corrupt',
            isFalse),
      );
    });
  });
}
