import 'package:aura_hub/core/platform/io_compat.dart';

/// Web builds use the in-memory filesystem in [io_compat], whose writes are
/// whole-value replacements; no temporary file is needed.
Future<void> atomicWriteString(
  File target,
  String contents, {
  bool Function()? isCommitAllowed,
}) async {
  await target.parent.create(recursive: true);
  if (isCommitAllowed != null && !isCommitAllowed()) {
    throw StateError('Atomic write rejected by its ownership guard.');
  }
  // The web filesystem replacement is synchronous. Do not reintroduce an await
  // here: a check followed by an async write would let a lock or profile switch
  // interleave before the verifier is replaced.
  target.writeAsStringSync(contents, flush: true);
}
