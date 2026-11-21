// Platform-neutral view of the small `dart:io` surface AURA Hub uses.
//
// Native builds export the real `dart:io` library. Web builds get an in-memory
// file system and explicit unsupported-network/process stubs so the UI can run
// in Chrome without changing Windows or Android behavior.
export 'io_compat_io.dart' if (dart.library.js_interop) 'io_compat_stub.dart';
