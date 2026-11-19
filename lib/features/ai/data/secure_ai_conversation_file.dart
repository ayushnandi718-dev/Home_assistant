import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/ai/data/ai_conversation_storage_envelope.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';

/// Converts a validated pre-Phase-5B plaintext document into the payload that
/// is encrypted. Implementations must throw a fixed
/// [AiConversationStorageException] for any rejected record.
typedef AiConversationLegacyConverter = Object? Function(Object? decoded);

/// Encrypted, migration-aware file boundary for AYUSH conversations.
///
/// Only ciphertext is ever written to disk: the destination, its atomic temp
/// file and its rollback backup all contain the same versioned envelope. The
/// legacy plaintext file is read into memory, validated, encrypted, verified
/// and committed before it is removed. Any integrity failure throws
/// [AiConversationStorageException] and leaves files untouched.
class SecureAiConversationFile {
  SecureAiConversationFile({
    required this.file,
    required this.legacyFiles,
    required this.scope,
    required this.cipher,
    required this.validatePayload,
    required this.normaliseLegacy,
    this.beforeMigrationCommit,
    this.beforeWriteCommit,
    this.beforeReadCommit,
  });

  final File file;
  final List<File> legacyFiles;
  final String scope;
  final MemoryCipher cipher;
  final bool Function(Object? value) validatePayload;
  final AiConversationLegacyConverter normaliseLegacy;

  /// Test seams for simulating a crash immediately before a commit.
  final Future<void> Function()? beforeMigrationCommit;
  final Future<void> Function()? beforeWriteCommit;
  final Future<void> Function()? beforeReadCommit;

  File get tempFile => File('${file.path}.secure.tmp');
  File get backupFile => File('${file.path}.secure.backup');

  Future<Object?> read() async {
    _ensureCipherAvailable();

    if (await file.exists()) {
      final Object? payload = await _readEnvelope(file);
      return _finishRead(payload);
    }

    // A crash between writing the encrypted temp and committing it must not be
    // mistaken for an empty history.
    if (await tempFile.exists()) {
      final Object? payload = await _readEnvelope(tempFile);
      await _replaceWithTemp(tempFile);
      return _finishRead(payload);
    }

    for (final File candidate in legacyFiles) {
      if (!await candidate.exists()) continue;
      return _migrate(candidate);
    }
    return null;
  }

  Future<void> write(
    Object? payload, {
    Future<void> Function()? beforeCommit,
  }) async {
    _ensureCipherAvailable();
    if (!validatePayload(payload)) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.write,
      );
    }

    final String plainText = jsonEncode(payload);
    final List<int> ciphertext = await _encrypt(
      utf8.encode(plainText),
      AiConversationStorageMessages.write,
    );
    final String envelope = AiConversationStorageEnvelope.encode(
      ciphertext: ciphertext,
      scope: scope,
    );

    final File? backup = await _backupCurrent();
    try {
      await _writeEnvelopeTemp(
        envelope,
        plainText,
        AiConversationStorageMessages.write,
      );
      if (beforeWriteCommit != null) await beforeWriteCommit!();
      if (beforeCommit != null) await beforeCommit();
      await _replaceWithTemp(tempFile, backup: backup);
    } catch (error) {
      await _restoreFromBackup(backup);
      if (error is AiConversationStorageException) rethrow;
      throw const AiConversationStorageException(
        AiConversationStorageMessages.write,
      );
    } finally {
      await _remove(tempFile);
    }
    if (backup != null) await _remove(backup);
  }

  Future<Object?> _migrate(File legacy) async {
    final String raw =
        await _readText(legacy, AiConversationStorageMessages.migration);
    final Object? decoded =
        _decodeJson(raw, AiConversationStorageMessages.migration);

    final Object? normalised;
    try {
      normalised = normaliseLegacy(decoded);
    } on AiConversationStorageException {
      rethrow;
    } catch (_) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.migration,
      );
    }
    if (!validatePayload(normalised)) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.migration,
      );
    }

    final String plainText = jsonEncode(normalised);
    final List<int> ciphertext = await _encrypt(
      utf8.encode(plainText),
      AiConversationStorageMessages.migration,
    );
    final String envelope = AiConversationStorageEnvelope.encode(
      ciphertext: ciphertext,
      scope: scope,
    );

    try {
      await _writeEnvelopeTemp(
        envelope,
        plainText,
        AiConversationStorageMessages.migration,
      );
      if (beforeMigrationCommit != null) await beforeMigrationCommit!();
      await _replaceWithTemp(tempFile);
    } catch (error) {
      if (error is AiConversationStorageException) rethrow;
      throw const AiConversationStorageException(
        AiConversationStorageMessages.migration,
      );
    } finally {
      await _remove(tempFile);
    }

    // The encrypted destination is committed and verified. Plaintext is
    // removed only now; a failure here is retried on the next successful read.
    await _cleanupLegacyFiles();
    return normalised;
  }

  Future<Object?> _finishRead(Object? payload) async {
    if (beforeReadCommit != null) await beforeReadCommit!();
    await _cleanupLegacyFiles();
    return payload;
  }

  Future<void> _writeEnvelopeTemp(
    String envelope,
    String expectedPlainText,
    String failureMessage,
  ) async {
    try {
      await file.parent.create(recursive: true);
      await tempFile.writeAsString(envelope, flush: true);
      await _verify(tempFile, expectedPlainText, failureMessage);
    } on AiConversationStorageException {
      rethrow;
    } catch (_) {
      throw AiConversationStorageException(failureMessage);
    }
  }

  Future<Object?> _readEnvelope(File candidate) async {
    final String raw =
        await _readText(candidate, AiConversationStorageMessages.unreadable);
    final Object? decoded =
        _decodeJson(raw, AiConversationStorageMessages.unreadable);
    if (!AiConversationStorageEnvelope.isEnvelope(decoded)) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.unreadable,
      );
    }

    final List<int> ciphertext;
    try {
      ciphertext = AiConversationStorageEnvelope.decode(decoded, scope: scope);
    } catch (_) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.unreadable,
      );
    }

    final List<int> plaintext = await _decrypt(ciphertext);
    final Object? payload;
    try {
      payload = jsonDecode(utf8.decode(plaintext));
    } catch (_) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.decryption,
      );
    }
    if (!validatePayload(payload)) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.decryption,
      );
    }
    return payload;
  }

  Future<void> _verify(
    File candidate,
    String expectedPlainText,
    String failureMessage,
  ) async {
    final String raw = await _readText(candidate, failureMessage);
    final Object? decoded = _decodeJson(raw, failureMessage);
    final List<int> ciphertext;
    try {
      ciphertext = AiConversationStorageEnvelope.decode(decoded, scope: scope);
    } catch (_) {
      throw AiConversationStorageException(failureMessage);
    }
    final List<int> plaintext = await _decrypt(ciphertext);
    final String actual;
    try {
      actual = utf8.decode(plaintext);
    } catch (_) {
      throw AiConversationStorageException(failureMessage);
    }
    if (actual != expectedPlainText) {
      throw AiConversationStorageException(failureMessage);
    }
  }

  Future<List<int>> _encrypt(
      List<int> plainBytes, String failureMessage) async {
    try {
      return await cipher.encrypt(plainBytes);
    } catch (_) {
      throw AiConversationStorageException(failureMessage);
    }
  }

  Future<List<int>> _decrypt(List<int> ciphertext) async {
    try {
      return await cipher.decrypt(ciphertext);
    } catch (_) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.decryption,
      );
    }
  }

  Future<String> _readText(File candidate, String failureMessage) async {
    try {
      return await candidate.readAsString();
    } catch (_) {
      throw AiConversationStorageException(failureMessage);
    }
  }

  Object? _decodeJson(String raw, String failureMessage) {
    try {
      return jsonDecode(raw);
    } catch (_) {
      throw AiConversationStorageException(failureMessage);
    }
  }

  Future<File?> _backupCurrent() async {
    if (!await file.exists()) return null;
    final File backup = backupFile;
    await _remove(backup);
    try {
      await file.copy(backup.path);
      return backup;
    } catch (_) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.write,
      );
    }
  }

  Future<void> _replaceWithTemp(
    File temp, {
    File? backup,
  }) async {
    try {
      await temp.rename(file.path);
      return;
    } on FileSystemException {
      // Windows may refuse rename over an existing file.
    }

    final bool hadTarget = await file.exists();
    try {
      if (hadTarget) await file.delete();
      await temp.rename(file.path);
    } catch (_) {
      await _restoreFromBackup(backup);
      throw const AiConversationStorageException(
        AiConversationStorageMessages.write,
      );
    }
  }

  Future<void> _restoreFromBackup(File? backup) async {
    if (backup == null || !await backup.exists()) return;
    try {
      if (!await file.exists()) await backup.copy(file.path);
      await _remove(backup);
    } catch (_) {
      // Leaving the encrypted backup is safer than deleting it.
    }
  }

  Future<void> _cleanupLegacyFiles() async {
    for (final File legacy in legacyFiles) {
      await _remove(legacy);
    }
  }

  Future<void> _remove(File candidate) async {
    try {
      if (await candidate.exists()) await candidate.delete();
    } catch (_) {
      // Best-effort. A plaintext leftover is retried on the next valid read.
    }
  }

  void _ensureCipherAvailable() {
    if (!cipher.isAvailable) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.unsupported,
      );
    }
  }
}
