import 'dart:convert';
import 'dart:typed_data';

import 'package:aura_hub/core/crypto/pbkdf2.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('derivePbkdf2HmacSha256', () {
    test('matches a known answer from Python hashlib.pbkdf2_hmac', () {
      // hashlib.pbkdf2_hmac('sha256', b'1234', b'0123456789abcdef', 1000, 32)
      final Uint8List key = derivePbkdf2HmacSha256(
        password: utf8.encode('1234'),
        salt: utf8.encode('0123456789abcdef'),
        iterations: 1000,
      );
      expect(
        base64.encode(key),
        'lthrw4diKhMqjsP6Pb8Ut8JakDM53i2wZ0MKCGR8gn4=',
      );
      expect(key.length, 32);
    });

    test('a different password or salt yields a different key', () {
      final Uint8List baseline = derivePbkdf2HmacSha256(
        password: utf8.encode('1234'),
        salt: utf8.encode('0123456789abcdef'),
        iterations: 1000,
      );
      final Uint8List otherPassword = derivePbkdf2HmacSha256(
        password: utf8.encode('1235'),
        salt: utf8.encode('0123456789abcdef'),
        iterations: 1000,
      );
      final Uint8List otherSalt = derivePbkdf2HmacSha256(
        password: utf8.encode('1234'),
        salt: utf8.encode('0123456789abcde0'),
        iterations: 1000,
      );

      expect(otherPassword, isNot(baseline));
      expect(otherSalt, isNot(baseline));
    });

    test('more iterations change the result', () {
      final Uint8List low = derivePbkdf2HmacSha256(
        password: utf8.encode('4821'),
        salt: utf8.encode('fedcba9876543210'),
        iterations: 100,
      );
      final Uint8List high = derivePbkdf2HmacSha256(
        password: utf8.encode('4821'),
        salt: utf8.encode('fedcba9876543210'),
        iterations: 1000,
      );
      expect(high, isNot(low));
      expect(
        base64.encode(high),
        'EhpPJtFu4gYlIOBCliGy985b27EMzxwG05msWun4h+0=',
      );
    });

    test('supports key lengths spanning more than one HMAC block', () {
      final Uint8List key = derivePbkdf2HmacSha256(
        password: utf8.encode('1234'),
        salt: utf8.encode('0123456789abcdef'),
        iterations: 10,
        keyLength: 64,
      );
      expect(key.length, 64);
      expect(
          key.sublist(0, 32),
          derivePbkdf2HmacSha256(
            password: utf8.encode('1234'),
            salt: utf8.encode('0123456789abcdef'),
            iterations: 10,
          ));
    });

    test('rejects invalid inputs', () {
      expect(
        () => derivePbkdf2HmacSha256(
          password: const <int>[],
          salt: utf8.encode('salt'),
          iterations: 10,
        ),
        throwsArgumentError,
      );
      expect(
        () => derivePbkdf2HmacSha256(
          password: utf8.encode('pin'),
          salt: const <int>[],
          iterations: 10,
        ),
        throwsArgumentError,
      );
      expect(
        () => derivePbkdf2HmacSha256(
          password: utf8.encode('pin'),
          salt: utf8.encode('salt'),
          iterations: 0,
        ),
        throwsArgumentError,
      );
    });
  });
}
