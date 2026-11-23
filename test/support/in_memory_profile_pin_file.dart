import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';

/// In-memory [ProfilePinFile] for widget tests.
///
/// Persisted PIN lockout I/O uses real `dart:io` futures in production. Under
/// `testWidgets` those futures never settle because the widget tester runs in
/// fake async, so tests must inject this seam instead of pointing the store at
/// the real filesystem.
class InMemoryProfilePinFile implements ProfilePinFile {
  String? _contents;

  @override
  Future<bool> exists() async => _contents != null;

  @override
  Future<String> readAsString() async =>
      _contents ?? (throw StateError('In-memory pin file is empty'));

  @override
  Future<void> writeAsString(String contents, {required bool flush}) async {
    _contents = contents;
  }

  @override
  Future<void> replaceWith(String contents) async {
    _contents = contents;
  }

  @override
  Future<void> createParent() async {}

  @override
  Future<void> delete() async {
    _contents = null;
  }
}
