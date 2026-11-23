import 'dart:ffi';
import 'dart:typed_data';

/// Scrubs native secret buffers before their owning allocator releases them.
///
/// The [free] callback is intentionally supplied by the caller so each native
/// ownership contract stays in the file that understands it: `LocalFree` for
/// DPAPI output, `HeapFree` for credential-vault allocations, and `CredFree`
/// for the opaque graph returned by `CredReadW`. This keeps zeroization testable
/// without pretending those allocators are interchangeable.
abstract interface class NativeMemoryGuard {
  const NativeMemoryGuard();

  /// Overwrites a native buffer view with zeroes.
  void zero(Uint8List bytes);

  /// Scrubs [secretBytes], if supplied, then releases [pointer] with [free].
  ///
  /// Implementations must preserve this order. The pointer must be the exact
  /// value expected by [free]; callers must never substitute an allocator.
  void zeroThenFree(
    Uint8List? secretBytes,
    Pointer<Void> pointer,
    void Function(Pointer<Void>) free,
  );
}

/// Portable best-effort scrubber using Dart's typed-data view over native RAM.
///
/// This cannot promise cryptographic-grade erasure: the JIT/compiler may keep
/// copies or elide dead stores. It does ensure the native bytes visible through
/// the view are overwritten before the native allocator reclaims them. The
/// limitation is deliberate and must be documented rather than overclaimed.
class FillNativeMemoryGuard implements NativeMemoryGuard {
  const FillNativeMemoryGuard();

  @override
  void zero(Uint8List bytes) {
    for (int index = 0; index < bytes.length; index++) {
      bytes[index] = 0;
    }
  }

  @override
  void zeroThenFree(
    Uint8List? secretBytes,
    Pointer<Void> pointer,
    void Function(Pointer<Void>) free,
  ) {
    if (secretBytes != null) zero(secretBytes);
    free(pointer);
  }
}
