import 'dart:typed_data';

/// A fixed, non-content message shown when AYUSH memory cannot be trusted.
///
/// These messages deliberately contain no record text, file contents or
/// provider output. They tell the user only what recovery action is allowed.
abstract final class MemoryStorageMessages {
  static const String decryption =
      'AYUSH memory could not be decrypted. AURA has not changed or replaced '
      'the stored file. Restore AURA Hub app data from a trusted backup, or '
      'contact support with the storage error code.';

  static const String unreadable =
      'AYUSH memory storage is unreadable. AURA has not changed or replaced '
      'the stored file. Restore AURA Hub app data from a trusted backup.';

  static const String migration =
      'AYUSH memory could not be migrated to encrypted storage. The original '
      'file was preserved. Restore AURA Hub app data from a trusted backup or '
      'retry after freeing local storage space.';

  static const String write =
      'AYUSH memory could not be encrypted and saved. No unencrypted fallback '
      'was written. Try again, or restore from a trusted backup.';

  static const String unsupported =
      'Encrypted AYUSH memory is unavailable on this device. AURA will not '
      'store private memory in plaintext.';
}

/// Thrown only for storage integrity, encryption or recovery failures.
///
/// Callers must treat this as a hard stop: never substitute an empty memory
/// collection and never overwrite the affected file.
class MemoryStorageException implements Exception {
  const MemoryStorageException(this.userMessage, {this.errorCode});

  final String userMessage;
  final String? errorCode;

  @override
  String toString() => errorCode == null
      ? 'MemoryStorageException: $userMessage'
      : 'MemoryStorageException ($errorCode): $userMessage';
}

/// Platform-independent encryption boundary used by AYUSH memory files.
///
/// Implementations must never log, echo or embed plaintext in error messages.
abstract class MemoryCipher {
  /// Whether this cipher can protect data on the current device.
  bool get isAvailable;

  Future<Uint8List> encrypt(List<int> plaintext);
  Future<Uint8List> decrypt(List<int> ciphertext);
}

/// Used when the current platform cannot provide approved local encryption.
///
/// This keeps AYUSH fail-closed instead of silently falling back to plaintext.
class UnsupportedMemoryCipher implements MemoryCipher {
  const UnsupportedMemoryCipher();

  @override
  bool get isAvailable => false;

  @override
  Future<Uint8List> encrypt(List<int> plaintext) async =>
      throw const MemoryStorageException(MemoryStorageMessages.unsupported);

  @override
  Future<Uint8List> decrypt(List<int> ciphertext) async =>
      throw const MemoryStorageException(MemoryStorageMessages.unsupported);
}
