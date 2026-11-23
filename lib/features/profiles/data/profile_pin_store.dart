import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';
import 'dart:math';

import 'package:aura_hub/core/crypto/pbkdf2.dart';
import 'package:aura_hub/core/platform/atomic_file_writer.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/profiles/domain/pin_validation.dart';
import 'package:crypto/crypto.dart';

/// Minimal file seam used by [ProfilePinStore] so atomic-write and corrupt-state
/// behaviour can be tested without touching a real user file.
abstract interface class ProfilePinFile {
  Future<bool> exists();

  Future<String> readAsString();

  Future<void> writeAsString(String contents, {required bool flush});

  /// Atomically replaces the file contents with [contents].
  Future<void> replaceWith(String contents);

  Future<void> createParent();

  Future<void> delete();
}

/// Production [ProfilePinFile] backed by `dart:io`.
class IoProfilePinFile implements ProfilePinFile {
  IoProfilePinFile(this._file);

  final File _file;

  @override
  Future<bool> exists() => _file.exists();

  @override
  Future<String> readAsString() => _file.readAsString();

  @override
  Future<void> writeAsString(String contents, {required bool flush}) =>
      _file.writeAsString(contents, flush: flush);

  @override
  Future<void> replaceWith(String contents) =>
      atomicWriteString(_file, contents);

  @override
  Future<void> createParent() => _file.parent.create(recursive: true);

  @override
  Future<void> delete() => _file.delete();
}

/// Persists a salted PBKDF2 verifier for the AYUSH PIN - never the PIN itself.
///
/// The file is local to the user profile. A password KDF makes an offline
/// guessing attack against a low-entropy PIN far more expensive than a plain
/// SHA-256 hash. This remains a local convenience lock, not a replacement for
/// OS credential storage or a backend authenticator.
class ProfilePinStore {
  ProfilePinStore({
    Directory? directory,
    this.iterations = defaultIterations,
    ProfilePinFile? file,
    ProfilePinFile? lockoutFile,
  })  : _file = file ?? _defaultFile(directory, 'profile_pin.json'),
        _lockoutFile =
            lockoutFile ?? _defaultFile(directory, 'profile_pin_lockout.json');

  static IoProfilePinFile _defaultFile(Directory? directory, String name) =>
      IoProfilePinFile(
        File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}$name',
        ),
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

  final ProfilePinFile _file;
  final ProfilePinFile _lockoutFile;

  /// Injectable into the session controller so lockout survives a restart.
  ProfilePinFile get lockoutFile => _lockoutFile;

  /// Kept for callers that only need a yes/no answer. The message now names the
  /// actual problem; the shared rules live in [PinValidation] so the UI and the
  /// store can never disagree about what is acceptable.
  static String? validatePin(String pin) => PinValidation.storageError(pin);

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
    await _file.replaceWith(
      jsonEncode(<String, dynamic>{
        'version': _formatVersion,
        'kdf': _kdfName,
        'iterations': count,
        'salt': salt,
        'hash': hash,
      }),
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

/// Persisted lockout counters. Contains no PIN material and no private data.
class ProfilePinLockoutState {
  const ProfilePinLockoutState({
    this.failedAttempts = 0,
    this.lockedUntil,
    this.corrupt = false,
  });

  final int failedAttempts;
  final DateTime? lockedUntil;

  /// True when the stored state was unreadable or unreasonable and a fixed
  /// recovery lockout was substituted. The UI uses this to show a recovery path.
  final bool corrupt;
}

/// Stores the AYUSH failure count and lockout expiry across restarts.
///
/// Corrupt or unreasonable state never extends the lock indefinitely. It is
/// replaced with a short fixed lockout and reported through [ProfilePinLockoutState.corrupt].
class ProfilePinLockoutStore {
  ProfilePinLockoutStore({
    required ProfilePinFile file,
    DateTime Function()? now,
  })  : _file = file,
        _now = now ?? DateTime.now;

  final ProfilePinFile _file;
  final DateTime Function() _now;

  static const int _schemaVersion = 1;
  static const int maxPersistedAttempts = 1000;
  static const int corruptFailureCount = 5;
  static const Duration corruptStateLockout = Duration(minutes: 1);
  static const Duration maxLockoutWindow = Duration(hours: 1);

  Future<ProfilePinLockoutState> load() async {
    try {
      if (!await _file.exists()) return const ProfilePinLockoutState();
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic> ||
          decoded['version'] != _schemaVersion) {
        return await _corruptFallback();
      }
      final Object? rawAttempts = decoded['failedAttempts'];
      if (rawAttempts is! int ||
          rawAttempts < 0 ||
          rawAttempts > maxPersistedAttempts) {
        return await _corruptFallback();
      }
      final Object? rawUntil = decoded['lockedUntil'];
      DateTime? lockedUntil;
      if (rawUntil != null) {
        if (rawUntil is! String) return await _corruptFallback();
        lockedUntil = DateTime.tryParse(rawUntil);
        if (lockedUntil == null ||
            lockedUntil.isAfter(_now().add(maxLockoutWindow))) {
          return await _corruptFallback();
        }
      }
      return ProfilePinLockoutState(
        failedAttempts: rawAttempts,
        lockedUntil: lockedUntil,
      );
    } catch (_) {
      return await _corruptFallback();
    }
  }

  Future<void> save({
    required int failedAttempts,
    required DateTime? lockedUntil,
  }) async {
    final int count = failedAttempts.clamp(0, maxPersistedAttempts);
    await _file.replaceWith(
      jsonEncode(<String, dynamic>{
        'version': _schemaVersion,
        'failedAttempts': count,
        'lockedUntil': lockedUntil?.toIso8601String(),
      }),
    );
  }

  Future<void> clear() async {
    if (await _file.exists()) await _file.delete();
  }

  Future<ProfilePinLockoutState> _corruptFallback() async {
    final ProfilePinLockoutState fallback = ProfilePinLockoutState(
      failedAttempts: corruptFailureCount,
      lockedUntil: _now().add(corruptStateLockout),
      corrupt: true,
    );
    try {
      await save(
        failedAttempts: fallback.failedAttempts,
        lockedUntil: fallback.lockedUntil,
      );
    } catch (_) {
      // A failed normalization still returns the fixed temporary lockout.
    }
    return fallback;
  }
}
