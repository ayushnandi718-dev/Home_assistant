import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:ffi/ffi.dart';

// Win32 constants from winbase.h / dpapi.h.
const int _cryptProtectUiForbidden = 0x00000001;

/// Mirrors the native `DATA_BLOB` structure used by DPAPI.
///
/// On x64 the pointer is automatically aligned to 8 bytes after `cbData`,
/// matching the Win32 ABI (total size 16 bytes).
final class _DataBlob extends Struct {
  @Uint32()
  external int cbData;

  external Pointer<Uint8> pbData;
}

// BOOL = Int32 (returned as Uint32 to preserve the full 32-bit value),
// DWORD = Uint32. DATA_BLOB is passed by pointer.
typedef _CryptProtectDataNative = Uint32 Function(
  Pointer<_DataBlob>,
  Pointer<Uint16>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _CryptProtectData = int Function(
  Pointer<_DataBlob>,
  Pointer<Uint16>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);

typedef _CryptUnprotectDataNative = Uint32 Function(
  Pointer<_DataBlob>,
  Pointer<Pointer<Uint16>>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  Uint32,
  Pointer<_DataBlob>,
);
typedef _CryptUnprotectData = int Function(
  Pointer<_DataBlob>,
  Pointer<Pointer<Uint16>>,
  Pointer<_DataBlob>,
  Pointer<Void>,
  Pointer<Void>,
  int,
  Pointer<_DataBlob>,
);

typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void>);
typedef _LocalFree = Pointer<Void> Function(Pointer<Void>);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastError = int Function();

/// Windows DPAPI encryption for AYUSH memory files.
///
/// Uses `CurrentUser` protection (the default when `CRYPTPROTECT_LOCAL_MACHINE`
/// is absent) together with `CRYPTPROTECT_UI_FORBIDDEN`. Native libraries and
/// function pointers are resolved lazily, so importing this file is safe on any
/// platform. No plaintext is ever included in an error message.
///
/// A fixed app-specific entropy value adds domain separation from other DPAPI
/// users on the same Windows account. It is not a password and is not stored in
/// Credential Manager.
class WindowsDpapiMemoryCipher implements MemoryCipher {
  WindowsDpapiMemoryCipher({String? entropy})
      : entropy = entropy ?? defaultEntropy;

  /// Stable domain-separation value for AURA Hub memory.
  static const String defaultEntropy = 'aura-hub-memory-v1';

  /// Used by tests to simulate a different Windows protection context.
  final String entropy;

  @override
  bool get isAvailable => Platform.isWindows;

  late final DynamicLibrary _crypt32 = _openLibrary('crypt32.dll');
  late final DynamicLibrary _kernel32 = _openLibrary('kernel32.dll');

  late final _CryptProtectData _cryptProtectData =
      _safeLookup<_CryptProtectData>(
    () => _crypt32.lookupFunction<_CryptProtectDataNative, _CryptProtectData>(
        'CryptProtectData'),
    'CryptProtectData',
  );

  late final _CryptUnprotectData _cryptUnprotectData =
      _safeLookup<_CryptUnprotectData>(
    () =>
        _crypt32.lookupFunction<_CryptUnprotectDataNative, _CryptUnprotectData>(
            'CryptUnprotectData'),
    'CryptUnprotectData',
  );

  late final _LocalFree _localFree = _safeLookup<_LocalFree>(
    () => _kernel32.lookupFunction<_LocalFreeNative, _LocalFree>('LocalFree'),
    'LocalFree',
  );

  late final _GetLastError _getLastError = _safeLookup<_GetLastError>(
    () => _kernel32
        .lookupFunction<_GetLastErrorNative, _GetLastError>('GetLastError'),
    'GetLastError',
  );

  @override
  Future<Uint8List> encrypt(List<int> plaintext) async {
    _ensureWindows();
    return _protect(
      plaintext,
      (Pointer<_DataBlob> input, Pointer<_DataBlob> entropyBlob,
              Pointer<_DataBlob> output) =>
          _cryptProtectData(
        input,
        nullptr,
        entropyBlob,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        output,
      ),
      'protect',
    );
  }

  @override
  Future<Uint8List> decrypt(List<int> ciphertext) async {
    _ensureWindows();
    return _protect(
      ciphertext,
      (Pointer<_DataBlob> input, Pointer<_DataBlob> entropyBlob,
              Pointer<_DataBlob> output) =>
          _cryptUnprotectData(
        input,
        nullptr,
        entropyBlob,
        nullptr,
        nullptr,
        _cryptProtectUiForbidden,
        output,
      ),
      'decrypt',
    );
  }

  Future<Uint8List> _protect(
    List<int> inputBytes,
    int Function(
      Pointer<_DataBlob> input,
      Pointer<_DataBlob> entropy,
      Pointer<_DataBlob> output,
    ) call,
    String operation,
  ) async {
    final List<int> entropyBytes = utf8.encode(entropy);
    final int inputAllocation = inputBytes.isEmpty ? 1 : inputBytes.length;
    final int entropyAllocation =
        entropyBytes.isEmpty ? 1 : entropyBytes.length;
    final Pointer<Uint8> bytes = calloc<Uint8>(inputAllocation);
    final Pointer<Uint8> entropyBuffer = calloc<Uint8>(entropyAllocation);
    final Pointer<_DataBlob> input = calloc<_DataBlob>();
    final Pointer<_DataBlob> entropyBlob = calloc<_DataBlob>();
    final Pointer<_DataBlob> output = calloc<_DataBlob>();
    try {
      for (int index = 0; index < inputBytes.length; index++) {
        bytes[index] = inputBytes[index] & 0xff;
      }
      for (int index = 0; index < entropyBytes.length; index++) {
        entropyBuffer[index] = entropyBytes[index] & 0xff;
      }
      input.ref.cbData = inputBytes.length;
      input.ref.pbData = bytes;
      entropyBlob.ref.cbData = entropyBytes.length;
      entropyBlob.ref.pbData = entropyBuffer;
      output.ref.cbData = 0;
      output.ref.pbData = nullptr;

      if (call(input, entropyBlob, output) == 0) {
        final int error = _getLastError();
        throw MemoryStorageException(
          MemoryStorageMessages.unreadable,
          errorCode: 'DPAPI $operation failed ($error)',
        );
      }
      final int length = output.ref.cbData;
      final Pointer<Uint8> buffer = output.ref.pbData;
      if (length <= 0 || buffer == nullptr) {
        throw const MemoryStorageException(
          MemoryStorageMessages.unreadable,
          errorCode: 'DPAPI returned an empty buffer',
        );
      }
      return Uint8List.fromList(buffer.asTypedList(length));
    } finally {
      if (output.ref.pbData != nullptr) {
        _localFree(output.ref.pbData.cast<Void>());
        output.ref.pbData = nullptr;
      }
      calloc.free(bytes);
      calloc.free(entropyBuffer);
      calloc.free(input);
      calloc.free(entropyBlob);
      calloc.free(output);
    }
  }

  void _ensureWindows() {
    if (!Platform.isWindows) {
      throw const MemoryStorageException(MemoryStorageMessages.unsupported);
    }
  }

  DynamicLibrary _openLibrary(String name) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      throw MemoryStorageException(
        MemoryStorageMessages.unsupported,
        errorCode: 'Unable to load $name',
      );
    }
  }

  T _safeLookup<T extends Function>(T Function() lookup, String name) {
    try {
      return lookup();
    } catch (_) {
      throw MemoryStorageException(
        MemoryStorageMessages.unsupported,
        errorCode: 'Unable to resolve $name',
      );
    }
  }
}
