// Platform-neutral atomic text-file replacement.
//
// Native builds get a temporary-file + atomic-replace implementation. Web gets
// the in-memory filesystem equivalent, which has no partially written window.
export 'atomic_file_writer_io.dart'
    if (dart.library.js_interop) 'atomic_file_writer_stub.dart';
