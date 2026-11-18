import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:aura_hub/core/crypto/pbkdf2.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:crypto/crypto.dart';

/// Persists a salted PBKDF2 verifier for the AYUSH PIN - never the PIN itself.
///
/// The file is local to the user profile. A password KDF makes an offline
/// guessing attack against a low-entropy PIN far more expensive than a plain
/// SHA-256 hash. This remains a local convenience lock, not a replacement for
/// OS credential storage or a backend authenticator.
class ProfilePinStore {
  ProfilePinStore({Directory? directory, this.iterations = defaultIterations})
      : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}profile_pin.json',
        );

  /// OWASP recommendation for PBKDF2-HMAC-SHA256. Stored in the file so old
  /// verifiers remain checkable after this default is raised in the future.
  static const int defaultIterations = 600000;

  /// Upper bound accepted from a file, so a tampered file cannot cause an
  /// unbounded derivation loop.
  static const int maxAcceptedIterations = 10000000;
  static const int _formatVersion = 2;
  static const String _kdfName = 'pbkdf2-hmac-sha256';
  static const int _keyLength = 32;
  static const int _saltLength = 16;

  /// Overridable for fast tests; production uses [defaultIterations].
  final int iterations;

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
    if (iterations <= 0 || iterations > maxAcceptedIterations) {
      throw ArgumentError.value(iterations, 'iterations', 'out of range');
    }

    final Random random = Random.secure();
    final List<int> saltBytes = List<int>.generate(
      _saltLength,
      (int _) => random.nextInt(256),
      growable: false,
    );
    final String salt = base64.encode(saltBytes);
    final String hash = _derive(saltBytes, pin, iterations);
    await _write(salt: salt, hash: hash, count: iterations);
  }

  /// Verifies [pin] and transparently upgrades legacy v1 SHA-256 verifiers to
  /// PBKDF2 after a successful match, so existing users keep their PIN.
  Future<bool> verify(String pin) async {
    if (validatePin(pin) != null) return false;
    try {
      if (!await _file.exists()) return false;
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic>) return false;
      final Object? salt = decoded['salt'];
      final Object? expected = decoded['hash'];
      if (salt is! String || expected is! String) return false;

      final List<int> saltBytes = base64.decode(salt);
      if (saltBytes.isEmpty) return false;

      if (_isLegacy(decoded)) {
        final bool matches = _secureEquals(expected, _legacyHash(salt, pin));
        if (!matches) return false;
        // Rehash with the current KDF. Use this instance's configured count so
        // tests stay fast; production callers use [defaultIterations].
        await setPin(pin);
        return true;
      }

      if (decoded['kdf'] != _kdfName) return false;
      final Object? rawIterations = decoded['iterations'];
      if (rawIterations is! int ||
          rawIterations <= 0 ||
          rawIterations > maxAcceptedIterations) {
        return false;
      }
      final String actual = _derive(saltBytes, pin, rawIterations);
      return _secureEquals(expected, actual);
    } catch (_) {
      return false;
    }
  }

  Future<void> removePin() async {
    if (await _file.exists()) await _file.delete();
  }

  bool _isLegacy(Map<String, dynamic> decoded) {
    final Object? kdf = decoded['kdf'];
    final Object? version = decoded['version'];
    return kdf == null || (version is int && version < _formatVersion);
  }

  String _derive(List<int> saltBytes, String pin, int count) => base64.encode(
        derivePbkdf2HmacSha256(
          password: utf8.encode(pin),
          salt: saltBytes,
          iterations: count,
          keyLength: _keyLength,
        ),
      );

  /// Kept only to migrate verifiers written by the earlier SHA-256 build.
  String _legacyHash(String salt, String pin) =>
      sha256.convert(utf8.encode('$salt:$pin')).toString();

  Future<void> _write({
    required String salt,
    required String hash,
    required int count,
  }) async {
    await _file.parent.create(recursive: true);
    await _file.writeAsString(
      jsonEncode(<String, dynamic>{
        'version': _formatVersion,
        'kdf': _kdfName,
        'iterations': count,
        'salt': salt,
        'hash': hash,
      }),
      flush: true,
    );
  }

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
