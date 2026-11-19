import 'dart:io';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('authenticated AYUSH PIN change', () {
    late Directory directory;
    late ProfilePinStore store;
    late ProfileSessionController controller;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_pin_change_test_');
      store = ProfilePinStore(directory: directory, iterations: 1000);
      controller = ProfileSessionController(store: store, logger: AuraLogger());
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('needs an existing PIN before it can be changed', () async {
      expect(
        await controller.changePin(
          currentPin: '1111',
          newPin: '2222',
          confirmation: '2222',
        ),
        PinChangeResult.needsSetup,
      );
    });

    test('success verifies the current PIN, persists the new one and locks',
        () async {
      await controller.setupPin('1111');
      expect(controller.state.privateSessionActive, isTrue);

      expect(
        await controller.changePin(
          currentPin: '1111',
          newPin: '2222',
          confirmation: '2222',
        ),
        PinChangeResult.success,
      );
      expect(controller.state.profile, AuraProfile.family);
      expect(controller.state.privateSessionActive, isFalse);

      // A fresh session proves the new verifier was written to the same store
      // and that the previous PIN no longer unlocks AYUSH.
      final ProfileSessionController reloaded =
          ProfileSessionController(store: store, logger: AuraLogger());
      expect(
          await reloaded.unlockAyush('1111'), ProfileUnlockResult.invalidPin);
      expect(await reloaded.unlockAyush('2222'), ProfileUnlockResult.success);
    });

    test('a wrong current PIN is rejected without ending the session',
        () async {
      await controller.setupPin('1111');

      expect(
        await controller.changePin(
          currentPin: '9999',
          newPin: '2222',
          confirmation: '2222',
        ),
        PinChangeResult.invalidCurrentPin,
      );
      expect(controller.state.privateSessionActive, isTrue);
      expect(controller.remainingAttempts,
          ProfileSessionController.maxFailedAttempts - 1);
      expect(await store.verify('1111'), isTrue);
      expect(await store.verify('2222'), isFalse);
    });

    test('confirmation mismatch and invalid new PINs change nothing', () async {
      await controller.setupPin('1111');

      expect(
        await controller.changePin(
          currentPin: '1111',
          newPin: '2222',
          confirmation: '3333',
        ),
        PinChangeResult.confirmationMismatch,
      );
      expect(
        await controller.changePin(
          currentPin: '1111',
          newPin: '12',
          confirmation: '12',
        ),
        PinChangeResult.invalidNewPin,
      );
      expect(
        await controller.changePin(
          currentPin: '1111',
          newPin: 'abcd',
          confirmation: 'abcd',
        ),
        PinChangeResult.invalidNewPin,
      );
      expect(
        await controller.changePin(
          currentPin: '1111',
          newPin: '2222',
          confirmation: '',
        ),
        PinChangeResult.invalidNewPin,
      );

      expect(controller.state.privateSessionActive, isTrue);
      expect(controller.remainingAttempts,
          ProfileSessionController.maxFailedAttempts,
          reason: 'form errors do not consume authentication attempts');
      expect(await store.verify('1111'), isTrue);
    });

    test('failed changes share the unlock lockout counter', () async {
      await controller.setupPin('1111');

      for (int attempt = 0;
          attempt < ProfileSessionController.maxFailedAttempts;
          attempt++) {
        expect(
          await controller.changePin(
            currentPin: '0000',
            newPin: '2222',
            confirmation: '2222',
          ),
          PinChangeResult.invalidCurrentPin,
        );
      }

      expect(controller.isLocked, isTrue);
      expect(
        await controller.changePin(
          currentPin: '1111',
          newPin: '2222',
          confirmation: '2222',
        ),
        PinChangeResult.rateLimited,
      );
      expect(await controller.unlockAyush('1111'),
          ProfileUnlockResult.rateLimited);
      expect(await store.verify('1111'), isTrue);
    });
  });
}
