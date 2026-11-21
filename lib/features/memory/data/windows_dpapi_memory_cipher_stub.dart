import 'dart:typed_data';

import 'package:aura_hub/features/memory/data/memory_cipher.dart';

/// Fail-closed browser stand-in for the Windows DPAPI cipher.
class WindowsDpapiMemoryCipher implements MemoryCipher {
  const WindowsDpapiMemoryCipher({String? entropy});

  static const String defaultEntropy = 'aura-hub-memory-v1';

  @override
  bool get isAvailable => false;

  @override
  Future<Uint8List> encrypt(List<int> plaintext) async =>
      throw const MemoryStorageException(MemoryStorageMessages.unsupported);

  @override
  Future<Uint8List> decrypt(List<int> ciphertext) async =>
      throw const MemoryStorageException(MemoryStorageMessages.unsupported);
}
