import 'package:aura_hub/core/platform/io_compat.dart';

/// Web builds use the in-memory filesystem in [io_compat], whose writes are
/// whole-value replacements; no temporary file is needed.
Future<void> atomicWriteString(File target, String contents) async {
  await target.parent.create(recursive: true);
  await target.writeAsString(contents, flush: true);
}
