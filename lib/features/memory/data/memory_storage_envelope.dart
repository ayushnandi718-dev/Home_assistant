import 'dart:convert';

import 'package:aura_hub/features/memory/data/memory_cipher.dart';

/// Versioned, scope-bound envelope stored inside the existing `.json` files.
///
/// The file name stays stable for migration. The contents are no longer the
/// legacy plaintext payload; they are this small JSON wrapper whose [payload]
/// is base64-encoded DPAPI ciphertext.
abstract final class MemoryStorageEnvelope {
  static const int version = 1;
  static const String cipher = 'windows-dpapi-current-user';
  static const String versionKey = 'envelopeVersion';
  static const String cipherKey = 'cipher';
  static const String scopeKey = 'scope';
  static const String payloadKey = 'payload';

  static bool isEnvelope(Object? decoded) =>
      decoded is Map<String, dynamic> && decoded.containsKey(versionKey);

  static String encode({
    required List<int> ciphertext,
    required String scope,
  }) {
    return jsonEncode(<String, dynamic>{
      versionKey: version,
      cipherKey: cipher,
      scopeKey: scope,
      payloadKey: base64.encode(ciphertext),
    });
  }

  static List<int> decode(Object? decoded, {required String scope}) {
    if (decoded is! Map<String, dynamic>) {
      throw const MemoryStorageException(MemoryStorageMessages.unreadable);
    }
    if (decoded[versionKey] != version) {
      throw const MemoryStorageException(
        MemoryStorageMessages.unreadable,
        errorCode: 'Unsupported memory envelope version',
      );
    }
    if (decoded[cipherKey] != cipher) {
      throw const MemoryStorageException(
        MemoryStorageMessages.unreadable,
        errorCode: 'Unsupported memory envelope cipher',
      );
    }
    if (decoded[scopeKey] != scope) {
      throw const MemoryStorageException(
        MemoryStorageMessages.unreadable,
        errorCode: 'Memory envelope profile mismatch',
      );
    }
    final Object? payload = decoded[payloadKey];
    if (payload is! String) {
      throw const MemoryStorageException(
        MemoryStorageMessages.unreadable,
        errorCode: 'Missing memory envelope payload',
      );
    }
    try {
      return base64.decode(payload);
    } catch (_) {
      throw const MemoryStorageException(
        MemoryStorageMessages.unreadable,
        errorCode: 'Invalid memory envelope payload',
      );
    }
  }
}
