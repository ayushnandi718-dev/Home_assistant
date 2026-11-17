import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:crypto/crypto.dart';

/// Persists a salted hash of the Ayush PIN - never the PIN itself.
///
/// The file is local to the user profile. This is an at-rest convenience lock,
/// not a replacement for OS credential storage or a backend authenticator.
class ProfilePinStore {
  ProfilePinStore({Directory? directory})
      : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}profile_pin.json',
        );

  final File _file;

  static const String validationError = 'Use 4 to 12 digits for the Ayush PIN.';

  static String? validatePin(String pin) {
    if (!RegExp(r'^\d{4,12}$').hasMatch(pin)) return validationError;
    return null;
  }

  Future<bool> hasPin() async {
    try {
      if (!await _file.exists()) return false;
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic>) return false;
      return (decoded['salt'] is String &&
              (decoded['salt'] as String).isNotEmpty) &&
          (decoded['hash'] is String && (decoded['hash'] as String).isNotEmpty);
    } catch (_) {
      return false;
    }
  }

  Future<void> setPin(String pin) async {
    final String? error = validatePin(pin);
    if (error != null) throw ArgumentError(error);

    final Random random = Random.secure();
    final List<int> saltBytes =
        List<int>.generate(16, (int _) => random.nextInt(256), growable: false);
    final String salt = base64.encode(saltBytes);
    final String hash = _hash(salt, pin);
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode(<String, dynamic>{
        'version': 1,
        'salt': salt,
        'hash': hash,
      }),
      flush: true,
    );
  }

  Future<bool> verify(String pin) async {
    if (validatePin(pin) != null) return false;
    try {
      if (!await _file.exists()) return false;
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic>) return false;
      final Object? salt = decoded['salt'];
      final Object? expected = decoded['hash'];
      if (salt is! String || expected is! String) return false;
      return _secureEquals(expected, _hash(salt, pin));
    } catch (_) {
      return false;
    }
  }

  Future<void> removePin() async {
    if (await _file.exists()) await _file.delete();
  }

  String _hash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  /// Comparison that does not short-circuit on the first differing byte.
  bool _secureEquals(String left, String right) {
    if (left.length != right.length) return false;
    int difference = 0;
    for (int index = 0; index < left.length; index++) {
      difference |= left.codeUnitAt(index) ^ right.codeUnitAt(index);
    }
    return difference == 0;
  }
}
