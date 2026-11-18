import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// PBKDF2-HMAC-SHA256 key derivation as defined by RFC 2898.
///
/// Implemented here rather than adding a dependency: `crypto` already provides
/// the HMAC primitive, and a small, auditable loop is enough for the single
/// low-entropy PIN use case. The caller chooses the iteration count; the PIN
/// store persists it alongside the derived key so verification stays stable if
/// the default is raised in a future release.
const int pbkdf2Sha256HashLength = 32;

/// Derives [keyLength] bytes from [password] and [salt].
///
/// Throws [ArgumentError] for empty inputs or non-positive counts so a corrupt
/// configuration can never silently produce a weak verifier.
Uint8List derivePbkdf2HmacSha256({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  int keyLength = pbkdf2Sha256HashLength,
}) {
  if (password.isEmpty) {
    throw ArgumentError.value(password, 'password', 'must not be empty');
  }
  if (salt.isEmpty) {
    throw ArgumentError.value(salt, 'salt', 'must not be empty');
  }
  if (iterations <= 0) {
    throw ArgumentError.value(iterations, 'iterations', 'must be positive');
  }
  if (keyLength <= 0) {
    throw ArgumentError.value(keyLength, 'keyLength', 'must be positive');
  }

  final Hmac hmac = Hmac(sha256, password);
  final int blocks =
      (keyLength + pbkdf2Sha256HashLength - 1) ~/ pbkdf2Sha256HashLength;
  final Uint8List result = Uint8List(blocks * pbkdf2Sha256HashLength);

  for (int block = 1; block <= blocks; block++) {
    // INT(block) is a 4-byte big-endian counter appended to the salt.
    final Uint8List input = Uint8List(salt.length + 4);
    input.setRange(0, salt.length, salt);
    input[salt.length] = (block >> 24) & 0xFF;
    input[salt.length + 1] = (block >> 16) & 0xFF;
    input[salt.length + 2] = (block >> 8) & 0xFF;
    input[salt.length + 3] = block & 0xFF;

    final Uint8List u = Uint8List.fromList(hmac.convert(input).bytes);
    final Uint8List accumulator = Uint8List.fromList(u);
    for (int round = 1; round < iterations; round++) {
      final Uint8List next = Uint8List.fromList(hmac.convert(u).bytes);
      for (int index = 0; index < pbkdf2Sha256HashLength; index++) {
        accumulator[index] ^= next[index];
        u[index] = next[index];
      }
    }
    result.setRange(
      (block - 1) * pbkdf2Sha256HashLength,
      block * pbkdf2Sha256HashLength,
      accumulator,
    );
  }

  return Uint8List.fromList(result.sublist(0, keyLength));
}
