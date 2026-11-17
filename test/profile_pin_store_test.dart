import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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
      store = ProfilePinStore(directory: directory);
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('reports no PIN before setup', () async {
      expect(await store.hasPin(), isFalse);
      expect(await store.verify('1234'), isFalse);
    });

    test('stores a salted hash and never the raw PIN', () async {
      await store.setPin('4821');

      expect(await store.hasPin(), isTrue);
      expect(await store.verify('4821'), isTrue);
      expect(await store.verify('4822'), isFalse);

      final File file = File(
        '${directory.path}${Platform.pathSeparator}profile_pin.json',
      );
      final String raw = await file.readAsString();
      expect(raw, isNot(contains('4821')));
      final Map<String, dynamic> json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['salt'], isA<String>());
      expect(json['hash'], isA<String>());
      expect((json['hash'] as String).length, 64);
    });

    test('uses a fresh salt when the PIN is replaced', () async {
      await store.setPin('1234');
      final File file = File(
        '${directory.path}${Platform.pathSeparator}profile_pin.json',
      );
      final String first = await file.readAsString();
      await store.setPin('1234');
      final String second = await file.readAsString();

      expect(first, isNot(second));
      expect(await store.verify('1234'), isTrue);
    });

    test('a tampered hash fails verification', () async {
      await store.setPin('7777');
      final File file = File(
        '${directory.path}${Platform.pathSeparator}profile_pin.json',
      );
      final Map<String, dynamic> json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      json['hash'] = '0' * 64;
      await file.writeAsString(jsonEncode(json));

      expect(await store.hasPin(), isTrue);
      expect(await store.verify('7777'), isFalse);
    });

    test('a corrupt file behaves like no PIN', () async {
      final File file = File(
        '${directory.path}${Platform.pathSeparator}profile_pin.json',
      );
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
  });
}
