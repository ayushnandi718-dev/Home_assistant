import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:aura_hub/features/integrations/data/credential_vault.dart';

// Win32 constants. Values come from wincred.h / winbase.h / winerror.h.
const int _credTypeGeneric = 1;
const int _credPersistLocalMachine = 2;
const int _errorNotFound = 1168;
const int _heapZeroMemory = 0x00000008;

/// Mirrors the native `CREDENTIALW` structure on x64 Windows.
///
/// Field order and offsets (bytes): Flags @0, Type @4, TargetName @8,
/// Comment @16, LastWritten @24 (8-byte FILETIME), CredentialBlobSize @32,
/// 4 bytes of automatic pointer alignment padding, CredentialBlob @40,
/// Persist @48, AttributeCount @52, Attributes @56, TargetAlias @64,
/// UserName @72, total size 80. `dart:ffi` aligns pointer fields to 8 bytes
/// on x64, which produces the required padding without an explicit field.
final class Credential extends Struct {
  @Uint32()
  external int flags;

  @Uint32()
  external int type;

  external Pointer<Uint16> targetName;

  external Pointer<Uint16> comment;

  @Uint64()
  external int lastWritten;

  @Uint32()
  external int credentialBlobSize;

  external Pointer<Uint8> credentialBlob;

  @Uint32()
  external int persist;

  @Uint32()
  external int attributeCount;

  external Pointer<Void> attributes;

  external Pointer<Uint16> targetAlias;

  external Pointer<Uint16> userName;
}

// Native typedefs. BOOL = Int32, DWORD = Uint32, SIZE_T = UintPtr.
typedef _CredWriteWNative = Int32 Function(Pointer<Credential>, Uint32);
typedef _CredWriteW = int Function(Pointer<Credential>, int);

typedef _CredReadWNative = Int32 Function(
  Pointer<Uint16>,
  Uint32,
  Uint32,
  Pointer<Pointer<Credential>>,
);
typedef _CredReadW = int Function(
  Pointer<Uint16>,
  int,
  int,
  Pointer<Pointer<Credential>>,
);

typedef _CredDeleteWNative = Int32 Function(Pointer<Uint16>, Uint32, Uint32);
typedef _CredDeleteW = int Function(Pointer<Uint16>, int, int);

typedef _CredFreeNative = Void Function(Pointer<Void>);
typedef _CredFree = void Function(Pointer<Void>);

typedef _GetProcessHeapNative = Pointer<Void> Function();
typedef _GetProcessHeap = Pointer<Void> Function();

typedef _HeapAllocNative = Pointer<Void> Function(
  Pointer<Void>,
  Uint32,
  UintPtr,
);
typedef _HeapAlloc = Pointer<Void> Function(Pointer<Void>, int, int);

typedef _HeapFreeNative = Int32 Function(Pointer<Void>, Uint32, Pointer<Void>);
typedef _HeapFree = int Function(Pointer<Void>, int, Pointer<Void>);

typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastError = int Function();

/// Windows Credential Manager backed [CredentialVault].
///
/// All native interaction lives in this file. Dynamic libraries are resolved
/// lazily on first use (never at import or class-load time), so importing this
/// file on any platform is safe. No secret is ever placed in an error message.
class WindowsCredentialVault implements CredentialVault {
  late final DynamicLibrary _advapi32 = _openLibrary('advapi32.dll');
  late final DynamicLibrary _kernel32 = _openLibrary('kernel32.dll');

  late final _CredWriteW _credWriteW = _safeLookup<_CredWriteW>(
    () =>
        _advapi32.lookupFunction<_CredWriteWNative, _CredWriteW>('CredWriteW'),
    'CredWriteW',
  );
  late final _CredReadW _credReadW = _safeLookup<_CredReadW>(
    () => _advapi32.lookupFunction<_CredReadWNative, _CredReadW>('CredReadW'),
    'CredReadW',
  );
  late final _CredDeleteW _credDeleteW = _safeLookup<_CredDeleteW>(
    () => _advapi32
        .lookupFunction<_CredDeleteWNative, _CredDeleteW>('CredDeleteW'),
    'CredDeleteW',
  );
  late final _CredFree _credFree = _safeLookup<_CredFree>(
    () => _advapi32.lookupFunction<_CredFreeNative, _CredFree>('CredFree'),
    'CredFree',
  );
  late final _GetProcessHeap _getProcessHeap = _safeLookup<_GetProcessHeap>(
    () => _kernel32.lookupFunction<_GetProcessHeapNative, _GetProcessHeap>(
        'GetProcessHeap'),
    'GetProcessHeap',
  );
  late final _HeapAlloc _heapAlloc = _safeLookup<_HeapAlloc>(
    () => _kernel32.lookupFunction<_HeapAllocNative, _HeapAlloc>('HeapAlloc'),
    'HeapAlloc',
  );
  late final _HeapFree _heapFree = _safeLookup<_HeapFree>(
    () => _kernel32.lookupFunction<_HeapFreeNative, _HeapFree>('HeapFree'),
    'HeapFree',
  );
  late final _GetLastError _getLastError = _safeLookup<_GetLastError>(
    () => _kernel32
        .lookupFunction<_GetLastErrorNative, _GetLastError>('GetLastError'),
    'GetLastError',
  );

  @override
  Future<void> write({
    required String target,
    required String secret,
  }) async {
    _ensureWindows();
    final Pointer<Uint16> targetChars = _allocateUint16(target);
    final int blobSize = _utf16ByteLength(secret);
    final Pointer<Uint8> blob = _allocateSecretBlob(secret, blobSize);
    final Pointer<Credential> credential = _allocateCredential();
    try {
      final Credential value = credential.ref;
      value.flags = 0;
      value.type = _credTypeGeneric;
      value.targetName = targetChars.cast<Uint16>();
      value.comment = nullptr;
      value.lastWritten = 0;
      value.credentialBlobSize = blobSize;
      value.credentialBlob = blob;
      value.persist = _credPersistLocalMachine;
      value.attributeCount = 0;
      value.attributes = nullptr;
      value.targetAlias = nullptr;
      value.userName = nullptr;

      if (_credWriteW(credential, 0) == 0) {
        throw StateError(
          'Windows Credential Manager rejected a credential write '
          '(error ${_getLastError()}).',
        );
      }
    } finally {
      _free(credential.cast<Void>());
      _free(blob.cast<Void>());
      _free(targetChars.cast<Void>());
    }
  }

  @override
  Future<String?> read({required String target}) async {
    _ensureWindows();
    final Pointer<Uint16> targetChars = _allocateUint16(target);
    final Pointer<Pointer<Credential>> result = _allocateZeroed(8).cast();
    try {
      result.value = nullptr;
      if (_credReadW(targetChars.cast<Uint16>(), _credTypeGeneric, 0, result) ==
          0) {
        final int error = _getLastError();
        if (error == _errorNotFound) return null;
        throw StateError(
          'Windows Credential Manager could not read a credential '
          '(error $error).',
        );
      }

      final Pointer<Credential> credential = result.value;
      try {
        final Credential value = credential.ref;
        final int size = value.credentialBlobSize;
        if (size <= 2) return '';
        return _decodeUint16Blob(value.credentialBlob, size);
      } finally {
        if (credential != nullptr) _credFree(credential.cast<Void>());
      }
    } finally {
      _free(result.cast<Void>());
      _free(targetChars.cast<Void>());
    }
  }

  @override
  Future<bool> delete({required String target}) async {
    _ensureWindows();
    final Pointer<Uint16> targetChars = _allocateUint16(target);
    try {
      if (_credDeleteW(targetChars.cast<Uint16>(), _credTypeGeneric, 0) != 0) {
        return true;
      }
      final int error = _getLastError();
      if (error == _errorNotFound) return false;
      throw StateError(
        'Windows Credential Manager could not delete a credential '
        '(error $error).',
      );
    } finally {
      _free(targetChars.cast<Void>());
    }
  }

  void _ensureWindows() {
    if (!Platform.isWindows) {
      throw StateError(
        'The Windows Credential Manager vault is only available on Windows.',
      );
    }
  }

  DynamicLibrary _openLibrary(String name) {
    try {
      return DynamicLibrary.open(name);
    } catch (_) {
      throw StateError(
        'Unable to load the Windows system library required by the credential '
        'vault ($name).',
      );
    }
  }

  T _safeLookup<T extends Function>(T Function() lookup, String name) {
    try {
      return lookup();
    } catch (_) {
      throw StateError(
        'Unable to resolve the Windows Credential Manager function ($name).',
      );
    }
  }

  Pointer<Void> _allocateZeroed(int byteCount) {
    final Pointer<Void> memory =
        _heapAlloc(_getProcessHeap(), _heapZeroMemory, byteCount);
    if (memory == nullptr) {
      throw StateError(
        'Unable to allocate native memory for a credential vault operation.',
      );
    }
    return memory;
  }

  Pointer<Credential> _allocateCredential() =>
      _allocateZeroed(sizeOf<Credential>()).cast<Credential>();

  /// Allocates a NUL-terminated UTF-16LE copy of [value].
  Pointer<Uint16> _allocateUint16(String value) {
    final int units = value.length + 1;
    final Pointer<Uint16> chars = _allocateZeroed(units * 2).cast<Uint16>();
    final Uint16List view = chars.asTypedList(units);
    for (int index = 0; index < value.length; index++) {
      view[index] = value.codeUnitAt(index);
    }
    view[value.length] = 0;
    return chars;
  }

  /// Credential blobs are counted in BYTES, not UTF-16 code units. The trailing
  /// two bytes are a NUL terminator supplied by the zeroed allocation.
  int _utf16ByteLength(String value) => value.length * 2 + 2;

  Pointer<Uint8> _allocateSecretBlob(String secret, int byteLength) {
    final Pointer<Uint8> blob = _allocateZeroed(byteLength).cast<Uint8>();
    final Uint8List view = blob.asTypedList(byteLength);
    for (int index = 0; index < secret.length; index++) {
      final int unit = secret.codeUnitAt(index);
      final int offset = index * 2;
      view[offset] = unit & 0xFF;
      view[offset + 1] = (unit >> 8) & 0xFF;
    }
    return blob;
  }

  String _decodeUint16Blob(Pointer<Uint8> blob, int byteLength) {
    final Uint8List view = blob.asTypedList(byteLength);
    final List<int> units = <int>[];
    for (int offset = 0; offset + 1 < byteLength; offset += 2) {
      final int unit = view[offset] | (view[offset + 1] << 8);
      if (unit == 0) break;
      units.add(unit);
    }
    return String.fromCharCodes(units);
  }

  void _free(Pointer<Void> memory) {
    _heapFree(_getProcessHeap(), 0, memory);
  }
}
