import 'dart:ffi';
import 'dart:math';

import 'package:aura_hub/core/platform/io_compat.dart';
import 'package:ffi/ffi.dart';

const int _moveFileReplaceExisting = 0x00000001;
const int _moveFileWriteThrough = 0x00000008;

typedef _MoveFileExWNative = Int32 Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  Uint32,
);
typedef _MoveFileExW = int Function(
  Pointer<Utf16>,
  Pointer<Utf16>,
  int,
);
typedef _GetLastErrorNative = Uint32 Function();
typedef _GetLastError = int Function();

/// Writes [contents] to a sibling temporary file, flushes it, then replaces
/// [target] without ever exposing a partially written verifier.
///
/// Windows uses `MoveFileExW` with `MOVEFILE_REPLACE_EXISTING`, which keeps the
/// replacement in the filesystem's atomic rename operation. Other native
/// platforms use `File.rename`, which replaces the destination atomically on
/// POSIX filesystems. The temporary file is removed if any step fails.
Future<void> atomicWriteString(File target, String contents) async {
  await target.parent.create(recursive: true);
  final Random random = Random.secure();
  final String temporaryPath =
      '${target.path}.tmp-${DateTime.now().microsecondsSinceEpoch}-'
      '${random.nextInt(0x7fffffff)}';
  final File temporary = File(temporaryPath);

  try {
    await temporary.writeAsString(contents, flush: true);
    if (Platform.isWindows) {
      await _replaceWindows(temporary, target);
    } else {
      await temporary.rename(target.path);
    }
  } catch (_) {
    if (await temporary.exists()) {
      try {
        await temporary.delete();
      } catch (_) {
        // Best effort only; never mask the original replacement failure.
      }
    }
    rethrow;
  }
}

Future<void> _replaceWindows(File temporary, File target) async {
  // MoveFileEx(existing, new, flags): the temporary file is the source and the
  // verifier path is the destination that gets replaced atomically.
  final Pointer<Utf16> sourcePath = temporary.path.toNativeUtf16();
  final Pointer<Utf16> destinationPath = target.path.toNativeUtf16();
  try {
    final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
    final _MoveFileExW moveFileEx = kernel32
        .lookupFunction<_MoveFileExWNative, _MoveFileExW>('MoveFileExW');
    final _GetLastError getLastError = kernel32
        .lookupFunction<_GetLastErrorNative, _GetLastError>('GetLastError');
    final int result = moveFileEx(
      sourcePath,
      destinationPath,
      _moveFileReplaceExisting | _moveFileWriteThrough,
    );
    if (result == 0) {
      final int error = getLastError();
      throw FileSystemException(
        'Could not replace the verifier file (Windows error $error).',
        target.path,
      );
    }
  } finally {
    malloc.free(sourcePath.cast<Void>());
    malloc.free(destinationPath.cast<Void>());
  }
}
