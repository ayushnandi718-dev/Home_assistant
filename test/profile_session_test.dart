import 'dart:io';

import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ProfileSession and ProfileAccess', () {
    test('app starts in the open family workspace', () {
      final ProfileSession session = ProfileSession.initial;
      expect(session.profile, AuraProfile.family);
      expect(session.privateSessionActive, isFalse);
    });

    test('private data is blocked until an authenticated session exists', () {
      final ProfileAccess denied = ProfileAccess(ProfileSession.initial);
      expect(denied.canRead(AuraProfile.family), isTrue);
      expect(denied.canRead(AuraProfile.ayush), isFalse);
      expect(
        () => denied.requirePrivate(AuraProfile.ayush, 'secret'),
        throwsA(isA<AuraProfileAccessDenied>()),
      );

      final ProfileSession unlocked = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime.now(),
        authenticated: true,
      );
      expect(unlocked.privateSessionActive, isTrue);
      expect(
        ProfileAccess(unlocked).requirePrivate(AuraProfile.ayush, 'secret'),
        'secret',
      );
    });
  });

  group('ProfileSessionController', () {
    late Directory directory;
    late ProfilePinStore store;
    late ProfileSessionController controller;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_session_test_');
      store = ProfilePinStore(directory: directory, iterations: 1000);
      controller = ProfileSessionController(store: store, logger: AuraLogger());
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('unlock requires setup when no PIN exists', () async {
      expect(
        await controller.unlockAyush('1234'),
        ProfileUnlockResult.needsSetup,
      );
      expect(controller.state.privateSessionActive, isFalse);
    });

    test('setup unlocks and lock returns to family', () async {
      expect(
        await controller.setupPin('2468'),
        ProfileUnlockResult.success,
      );
      expect(controller.state.profile, AuraProfile.ayush);
      expect(controller.state.privateSessionActive, isTrue);

      controller.lock();
      expect(controller.state.profile, AuraProfile.family);
      expect(controller.state.privateSessionActive, isFalse);
      expect(await controller.hasPin(), isTrue);
    });

    test('wrong PIN does not unlock and reports remaining attempts', () async {
      await controller.setupPin('1357');
      controller.lock();

      expect(
        await controller.unlockAyush('0000'),
        ProfileUnlockResult.invalidPin,
      );
      expect(controller.state.privateSessionActive, isFalse);
      expect(controller.remainingAttempts,
          ProfileSessionController.maxFailedAttempts - 1);
    });

    test('too many failures engage a temporary lockout', () async {
      await controller.setupPin('1357');
      controller.lock();

      for (int attempt = 0;
          attempt < ProfileSessionController.maxFailedAttempts;
          attempt++) {
        expect(
          await controller.unlockAyush('0000'),
          ProfileUnlockResult.invalidPin,
        );
      }

      expect(controller.isLocked, isTrue);
      expect(controller.remainingAttempts, 0);
      expect(
        await controller.unlockAyush('1357'),
        ProfileUnlockResult.rateLimited,
      );
      expect(controller.state.privateSessionActive, isFalse);
    });

    test('switching to family always opens the shared workspace', () async {
      await controller.setupPin('1111');
      expect(controller.state.profile, AuraProfile.ayush);
      controller.openFamily();
      expect(controller.state.profile, AuraProfile.family);
    });

    test('setting a new PIN clears any lockout', () async {
      await controller.setupPin('2222');
      controller.lock();
      for (int attempt = 0;
          attempt < ProfileSessionController.maxFailedAttempts;
          attempt++) {
        await controller.unlockAyush('0000');
      }
      expect(controller.isLocked, isTrue);

      expect(
        await controller.setupPin('3333'),
        ProfileUnlockResult.success,
      );
      expect(controller.isLocked, isFalse);
      expect(controller.state.privateSessionActive, isTrue);
    });
  });
}
