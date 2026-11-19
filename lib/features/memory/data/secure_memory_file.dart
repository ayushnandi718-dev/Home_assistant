import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/memory_storage_envelope.dart';

/// Encrypting, migration-aware JSON file used only by private AYUSH storage.
///
/// Legacy plaintext is accepted exactly once, validated, encrypted, verified,
/// and atomically replaced. Any integrity or encryption failure throws
/// [MemoryStorageException]; it never returns an empty payload because doing so
/// could make a damaged or foreign file look like deleted memories.
class SecureMemoryFile {
  SecureMemoryFile({
    required this.file,
    required this.scope,
    required this.cipher,
    required this.validatePayload,
    this.beforeMigrationCommit,
  });

  final File file;
  final String scope;
  final MemoryCipher cipher;
  final bool Function(Object? value) validatePayload;

  /// Test seam for simulating a crash immediately before the atomic replace.
  final Future<void> Function()? beforeMigrationCommit;

  Future<Object?> read() async {
    _ensureCipherAvailable();
    if (!await file.exists()) return null;

    final String raw = await _readText(MemoryStorageMessages.unreadable);
    final Object? decoded = _decodeJson(raw, MemoryStorageMessages.unreadable);

    if (MemoryStorageEnvelope.isEnvelope(decoded)) {
      final Object? payload = await _decodeEnvelope(decoded);
      await _removeBackup('legacy.backup');
      return payload;
    }

    if (!validatePayload(decoded)) {
      throw const MemoryStorageException(MemoryStorageMessages.unreadable);
    }
    return _migrate(decoded);
  }

  Future<void> write(Object? payload) async {
    _ensureCipherAvailable();
    final String plainText = jsonEncode(payload);
    final List<int> ciphertext = await _encrypt(
      utf8.encode(plainText),
      MemoryStorageMessages.write,
    );
    final String envelope = MemoryStorageEnvelope.encode(
      ciphertext: ciphertext,
      scope: scope,
    );
    final File? backup = await _backup('secure.backup');
    await _commit(
      envelope: envelope,
      expectedPlainText: plainText,
      backup: backup,
      failureMessage: MemoryStorageMessages.write,
    );
    if (backup != null) await _removeBackup('secure.backup');
  }

  Future<Object?> _decodeEnvelope(Object? envelope) async {
    final List<int> ciphertext = MemoryStorageEnvelope.decode(
      envelope,
      scope: scope,
    );
    final List<int> plaintext = await _decrypt(ciphertext);
    final Object? payload;
    try {
      payload = jsonDecode(utf8.decode(plaintext));
    } catch (_) {
      throw const MemoryStorageException(
        MemoryStorageMessages.decryption,
        errorCode: 'Decrypted payload is not valid JSON',
      );
    }
    if (!validatePayload(payload)) {
      throw const MemoryStorageException(
        MemoryStorageMessages.decryption,
        errorCode: 'Decrypted payload failed schema validation',
      );
    }
    return payload;
  }

  Future<Object?> _migrate(Object? legacy) async {
    final String plainText = jsonEncode(legacy);
    final List<int> ciphertext = await _encrypt(
      utf8.encode(plainText),
      MemoryStorageMessages.migration,
    );
    final String envelope = MemoryStorageEnvelope.encode(
      ciphertext: ciphertext,
      scope: scope,
    );
    final File? backup = await _backup('legacy.backup');
    await _commit(
      envelope: envelope,
      expectedPlainText: plainText,
      backup: backup,
      failureMessage: MemoryStorageMessages.migration,
      beforeCommit: beforeMigrationCommit,
    );
    await _removeBackup('legacy.backup');
    return legacy;
  }

  Future<List<int>> _encrypt(
    List<int> plainBytes,
    String failureMessage,
  ) async {
    try {
      return await cipher.encrypt(plainBytes);
    } on MemoryStorageException catch (error) {
      throw MemoryStorageException(
        failureMessage,
        errorCode: error.errorCode ?? 'Encryption failed',
      );
    } catch (_) {
      throw MemoryStorageException(failureMessage,
          errorCode: 'Encryption failed');
    }
  }

  Future<List<int>> _decrypt(List<int> ciphertext) async {
    try {
      return await cipher.decrypt(ciphertext);
    } on MemoryStorageException catch (error) {
      throw MemoryStorageException(
        MemoryStorageMessages.decryption,
        errorCode: error.errorCode ?? 'Decryption failed',
      );
    } catch (_) {
      throw const MemoryStorageException(
        MemoryStorageMessages.decryption,
        errorCode: 'Decryption failed',
      );
    }
  }

  Future<String> _readText(String failureMessage) =>
      _readCandidateText(file, failureMessage);

  Future<String> _readCandidateText(
    File candidate,
    String failureMessage,
  ) async {
    try {
      return await candidate.readAsString();
    } catch (_) {
      throw MemoryStorageException(failureMessage,
          errorCode: 'Local read failed');
    }
  }

  Object? _decodeJson(String raw, String failureMessage) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      throw MemoryStorageException(failureMessage, errorCode: 'Invalid JSON');
    }
  }

  Future<File?> _backup(String suffix) async {
    if (!await file.exists()) return null;
    final File backup = File('${file.path}.$suffix');
    if (await backup.exists()) await backup.delete();
    await file.copy(backup.path);
    return backup;
  }

  Future<void> _commit({
    required String envelope,
    required String expectedPlainText,
    required String failureMessage,
    required File? backup,
    Future<void> Function()? beforeCommit,
  }) async {
    final File temp = File('${file.path}.secure.tmp');
    try {
      await file.parent.create(recursive: true);
      await temp.writeAsString(envelope, flush: true);
      await _verify(temp, expectedPlainText, failureMessage);
      if (beforeCommit != null) await beforeCommit();
      await _replaceAtomically(temp, backup, failureMessage);
    } catch (error) {
      if (error is MemoryStorageException) rethrow;
      throw MemoryStorageException(failureMessage,
          errorCode: 'Local write interrupted');
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Best-effort cleanup. The original file is untouched on failure.
      }
    }
  }

  Future<void> _verify(
    File candidate,
    String expectedPlainText,
    String failureMessage,
  ) async {
    final String raw = await _readCandidateText(candidate, failureMessage);
    final Object? decoded = _decodeJson(raw, failureMessage);
    final List<int> ciphertext = MemoryStorageEnvelope.decode(
      decoded,
      scope: scope,
    );
    final List<int> plaintext = await _decrypt(ciphertext);
    final String actual;
    try {
      actual = utf8.decode(plaintext);
    } catch (_) {
      throw MemoryStorageException(failureMessage,
          errorCode: 'Encrypted payload verification failed');
    }
    if (actual != expectedPlainText) {
      throw MemoryStorageException(failureMessage,
          errorCode: 'Encrypted payload verification failed');
    }
  }

  Future<void> _replaceAtomically(
    File temp,
    File? backup,
    String failureMessage,
  ) async {
    try {
      await temp.rename(file.path);
      return;
    } on FileSystemException {
      // Windows may refuse rename over an existing file. Fall through to a
      // guarded delete/rename that can restore the backup if rename fails.
    }

    final bool hadTarget = await file.exists();
    try {
      if (hadTarget) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      if (hadTarget && backup != null && await backup.exists()) {
        try {
          if (!await file.exists()) await backup.copy(file.path);
        } catch (_) {
          // Preserve the original error; the backup itself is still present.
        }
      }
      throw MemoryStorageException(failureMessage,
          errorCode: 'Atomic replace failed');
    }
  }

  void _ensureCipherAvailable() {
    if (!cipher.isAvailable) {
      throw const MemoryStorageException(MemoryStorageMessages.unsupported);
    }
  }

  Future<void> _removeBackup(String suffix) async {
    try {
      final File backup = File('${file.path}.$suffix');
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      // A stale encrypted backup is harmless; a stale plaintext backup is
      // removed on the next successful encrypted read.
    }
  }
}
