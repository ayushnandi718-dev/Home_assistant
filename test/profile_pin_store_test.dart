import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Fast iterations keep the suite quick; production uses 600000.
  const int testIterations = 1000;

  String pinFilePath(Directory directory) =>
      '${directory.path}${Platform.pathSeparator}profile_pin.json';

  group('ProfilePinStore.validatePin', () {
    test('accepts 4 to 12 digits only', () {
      expect(ProfilePinStore.validatePin('1234'), isNull);
      expect(ProfilePinStore.validatePin('123456789012'), isNull);
      expect(ProfilePinStore.validatePin('123'), isNotNull);
      expect(ProfilePinStore.validatePin('1234567890123'), isNotNull);
      expect(ProfilePinStore.validatePin('12ab'), isNotNull);
      expect(ProfilePinStore.validatePin(''), isNotNull);
    });
  });

  group('ProfilePinStore', () {
    late Directory directory;
    late ProfilePinStore store;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_pin_test_');
      store = ProfilePinStore(directory: directory, iterations: testIterations);
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('reports no PIN before setup', () async {
      expect(await store.hasPin(), isFalse);
      expect(await store.verify('1234'), isFalse);
    });

    test('stores a salted PBKDF2 verifier and never the raw PIN', () async {
      await store.setPin('4821');

      expect(await store.hasPin(), isTrue);
      expect(await store.verify('4821'), isTrue);
      expect(await store.verify('4822'), isFalse);

      final String raw = await File(pinFilePath(directory)).readAsString();
      expect(raw, isNot(contains('4821')));
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['version'], 2);
      expect(json['kdf'], 'pbkdf2-hmac-sha256');
      expect(json['iterations'], testIterations);
      expect(json['salt'], isA<String>());
      expect(json['hash'], isA<String>());
      // 32 raw bytes encoded as base64 produce 44 characters.
      expect((json['hash'] as String).length, 44);
    });

    test('uses a fresh salt when the PIN is replaced', () async {
      await store.setPin('1234');
      final File file = File(pinFilePath(directory));
      final String first = await file.readAsString();
      final String firstSalt =
          (jsonDecode(first) as Map<String, dynamic>)['salt'] as String;
      await store.setPin('1234');
      final String second = await file.readAsString();
      final String secondSalt =
          (jsonDecode(second) as Map<String, dynamic>)['salt'] as String;

      expect(first, isNot(second));
      expect(firstSalt, isNot(secondSalt));
      expect(await store.verify('1234'), isTrue);
    });

    test('a tampered hash fails verification', () async {
      await store.setPin('7777');
      final File file = File(pinFilePath(directory));
      final Map<String, dynamic> json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json['hash'] = '0' * 44;
      await file.writeAsString(jsonEncode(json));

      expect(await store.hasPin(), isTrue);
      expect(await store.verify('7777'), isFalse);
    });

    test('an out-of-range iteration count fails verification', () async {
      await store.setPin('7777');
      final File file = File(pinFilePath(directory));
      final Map<String, dynamic> json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json['iterations'] = ProfilePinStore.maxAcceptedIterations + 1;
      await file.writeAsString(jsonEncode(json));

      expect(await store.verify('7777'), isFalse);
    });

    test('an unknown KDF fails verification', () async {
      await store.setPin('7777');
      final File file = File(pinFilePath(directory));
      final Map<String, dynamic> json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json['kdf'] = 'md5';
      await file.writeAsString(jsonEncode(json));

      expect(await store.verify('7777'), isFalse);
    });

    test('a corrupt file behaves like no PIN', () async {
      final File file = File(pinFilePath(directory));
      await file.writeAsString('{broken');

      expect(await store.hasPin(), isFalse);
      expect(await store.verify('1234'), isFalse);
    });

    test('removePin clears the verifier', () async {
      await store.setPin('9999');
      expect(await store.hasPin(), isTrue);
      await store.removePin();
      expect(await store.hasPin(), isFalse);
    });

    test('rejects an invalid PIN when setting', () async {
      expect(() => store.setPin('abc'), throwsArgumentError);
      expect(await store.hasPin(), isFalse);
    });

    test('migrates a legacy v1 SHA-256 verifier after a correct PIN', () async {
      // Reproduce the format written by the previous build exactly.
      const String pin = '1357';
      const String salt = 'c2FsdC1vbmx5LWZvci10ZXN0';
      final String legacyHash =
          sha256.convert(utf8.encode('$salt:$pin')).toString();
      final File file = File(pinFilePath(directory));
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'version': 1,
        'salt': salt,
        'hash': legacyHash,
      }));

      expect(await store.verify(pin), isTrue);

      final Map<String, dynamic> migrated =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      expect(migrated['version'], 2);
      expect(migrated['kdf'], 'pbkdf2-hmac-sha256');
      expect(migrated['iterations'], testIterations);
      // Salt is regenerated during migration, so the old verifier is gone.
      expect(migrated['salt'], isNot(salt));
      expect(await store.verify(pin), isTrue);
      expect(await store.verify('2468'), isFalse);
    });

    test('a wrong PIN does not migrate a legacy verifier', () async {
      const String pin = '1357';
      const String salt = 'c2FsdC1vbmx5LWZvci10ZXN0';
      final String legacyHash =
          sha256.convert(utf8.encode('$salt:$pin')).toString();
      final File file = File(pinFilePath(directory));
      final String before = jsonEncode(<String, dynamic>{
        'version': 1,
        'salt': salt,
        'hash': legacyHash,
      });
      await file.writeAsString(before);

      expect(await store.verify('9999'), isFalse);
      expect(await file.readAsString(), before);
    });
  });
}
