import 'dart:io';

import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/security/data/ayush_security_settings_store.dart';
import 'package:aura_hub/features/security/domain/ayush_security_settings.dart';
import 'package:aura_hub/features/security/presentation/auto_lock_controller.dart';
import 'package:aura_hub/features/security/presentation/security_providers.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ProfileSession _unlockedSession() => ProfileSession(
      profile: AuraProfile.ayush,
      startedAt: DateTime(2026),
      authenticated: true,
    );

class _MemorySecurityStorage implements AyushSecuritySettingsStorage {
  AyushSecuritySettings stored = AyushSecuritySettings.defaults;

  @override
  Future<AyushSecuritySettings> load({bool Function()? isWriteAllowed}) async =>
      stored;

  @override
  Future<void> save(
    AyushSecuritySettings settings, {
    bool Function()? isWriteAllowed,
  }) async {
    if (isWriteAllowed != null && !isWriteAllowed()) {
      throw const AuraProfileAccessDenied(AuraProfile.ayush);
    }
    stored = settings;
  }
}

class _FastPinStore extends ProfilePinStore {
  _FastPinStore() : super(directory: Directory.systemTemp, iterations: 1000);

  String? _pin;

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> setPin(String pin, {bool Function()? isCommitAllowed}) async =>
      _pin = pin;

  @override
  Future<bool> verify(String pin, {bool Function()? isCommitAllowed}) async =>
      _pin == pin;
}

void main() {
  group('AyushAutoLockController', () {
    test('arms only for AYUSH and locks once the idle timeout elapses', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = ProfileSession.initial;
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 5),
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        async.elapse(const Duration(hours: 1));
        expect(locks, 0, reason: 'FAMILY must never be locked');

        session = _unlockedSession();
        controller.start();
        async.elapse(const Duration(minutes: 4, seconds: 59));
        expect(locks, 0);
        async.elapse(const Duration(seconds: 1));
        expect(locks, 1);
        expect(controller.lockCount, 1);
        expect(session.privateSessionActive, isFalse);
      });
    });

    test('FAMILY ignores every activity and timeout hook', () {
      fakeAsync((async) {
        ProfileSession session = ProfileSession.initial;
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 1),
          lockAyush: () => locks++,
          now: () => DateTime(2026),
        );
        addTearDown(controller.dispose);

        controller.start();
        controller.registerActivity();
        controller.onAppResumed();
        controller.refreshTimeout();
        async.elapse(const Duration(days: 1));

        expect(locks, 0);
        expect(controller.lockCount, 0);
      });
    });

    test('deliberate activity restarts the countdown', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 5),
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        async.elapse(const Duration(minutes: 2));
        now = now.add(const Duration(minutes: 2));
        controller.registerActivity();
        expect(locks, 0);

        async.elapse(const Duration(minutes: 4));
        expect(locks, 0, reason: 'the countdown restarted at minute 2');
        async.elapse(const Duration(minutes: 1));
        expect(locks, 1);
      });
    });

    test('high-frequency input is throttled and cannot postpone the lock', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 5),
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
          activityThrottle: const Duration(minutes: 10),
        );
        addTearDown(controller.dispose);

        controller.start();
        async.elapse(const Duration(minutes: 4));
        now = now.add(const Duration(minutes: 4));
        controller.registerActivity();
        expect(locks, 0);

        async.elapse(const Duration(minutes: 1));
        expect(locks, 1, reason: 'the throttled event did not re-arm');
      });
    });

    test('Never means no timer is ever armed', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => null,
          lockAyush: () => locks++,
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        controller.registerActivity();
        controller.onAppResumed();
        async.elapse(const Duration(days: 1));

        expect(locks, 0);
        expect(controller.lockCount, 0);
      });
    });

    test('refreshTimeout applies a changed persisted value immediately', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        Duration timeout = const Duration(minutes: 1);
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => timeout,
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        async.elapse(const Duration(seconds: 30));
        timeout = const Duration(minutes: 5);
        controller.refreshTimeout();

        async.elapse(const Duration(minutes: 1));
        expect(locks, 0);
        async.elapse(const Duration(minutes: 4));
        expect(locks, 1);
      });
    });

    test('resuming the app counts as activity for AYUSH only', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 5),
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        async.elapse(const Duration(minutes: 2));
        now = now.add(const Duration(minutes: 2));
        controller.onAppResumed();
        async.elapse(const Duration(minutes: 4));
        expect(locks, 0);
        async.elapse(const Duration(minutes: 1));
        expect(locks, 1);
      });
    });

    test('background grace locks AYUSH even when inactivity is Never', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => null,
          backgroundGraceReader: () => const Duration(seconds: 30),
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        controller.onAppBackgrounded();
        async.elapse(const Duration(seconds: 29));
        expect(locks, 0);
        async.elapse(const Duration(seconds: 1));
        expect(locks, 1);
        expect(controller.lockCount, 1);
      });
    });

    test('resuming before the grace cancels it and reconciles inactivity', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 5),
          backgroundGraceReader: () => const Duration(seconds: 30),
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        controller.onAppBackgrounded();
        async.elapse(const Duration(seconds: 10));
        now = now.add(const Duration(seconds: 10));
        controller.onAppResumed();

        async.elapse(const Duration(seconds: 30));
        now = now.add(const Duration(seconds: 30));
        expect(locks, 0, reason: 'the background grace was cancelled');

        async.elapse(const Duration(minutes: 4, seconds: 20));
        expect(locks, 1, reason: 'inactivity is measured from the last input');
      });
    });

    test('resuming after a suspended grace locks once and cancels the timer',
        () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 5),
          backgroundGraceReader: () => const Duration(seconds: 30),
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        now = now.add(const Duration(seconds: 10));
        controller.onAppBackgrounded();
        // Simulate an OS-suspended timer: the clock moved but no callback ran.
        now = now.add(const Duration(minutes: 2));
        controller.onAppResumed();
        controller.onAppResumed();
        expect(locks, 1);
        expect(controller.lockCount, 1);

        async.elapse(const Duration(minutes: 1));
        expect(locks, 1, reason: 'repeated resume must not lock twice');
      });
    });

    test('repeated background lifecycle events do not extend the grace', () {
      fakeAsync((async) {
        DateTime now = DateTime(2026);
        ProfileSession session = _unlockedSession();
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 5),
          backgroundGraceReader: () => const Duration(seconds: 30),
          lockAyush: () {
            locks++;
            session = ProfileSession.initial;
          },
          now: () => now,
        );
        addTearDown(controller.dispose);

        controller.start();
        controller.onAppBackgrounded();
        async.elapse(const Duration(seconds: 10));
        now = now.add(const Duration(seconds: 10));
        controller.onAppBackgrounded();
        controller.onAppBackgrounded();
        async.elapse(const Duration(seconds: 20));
        expect(locks, 1);
      });
    });

    test('FAMILY ignores background transitions entirely', () {
      fakeAsync((async) {
        ProfileSession session = ProfileSession.initial;
        int locks = 0;
        final AyushAutoLockController controller = AyushAutoLockController(
          sessionReader: () => session,
          timeoutReader: () => const Duration(minutes: 1),
          backgroundGraceReader: () => Duration.zero,
          lockAyush: () => locks++,
          now: () => DateTime(2026),
        );
        addTearDown(controller.dispose);

        controller.onAppBackgrounded();
        controller.onAppResumed();
        async.elapse(const Duration(days: 1));
        expect(locks, 0);
        expect(controller.lockCount, 0);
      });
    });
  });

  group('auto-lock provider wiring', () {
    test('loads on unlock, clears on lock and stays guarded for FAMILY',
        () async {
      final _MemorySecurityStorage storage = _MemorySecurityStorage();
      storage.stored = const AyushSecuritySettings(
        autoLock: AyushAutoLock.tenMinutes,
        backgroundLockGrace: AyushBackgroundLockGrace.oneMinute,
      );
      final ProviderContainer container = ProviderContainer(
        overrides: <Override>[
          profilePinStoreProvider.overrideWithValue(_FastPinStore()),
          ayushSecuritySettingsStoreProvider.overrideWithValue(storage),
        ],
      );
      addTearDown(container.dispose);

      // main() reads the monitor once; startup stays in FAMILY.
      container.read(ayushAutoLockControllerProvider);
      expect(
          container.read(profileSessionProvider).privateSessionActive, isFalse);

      await expectLater(
        container.read(ayushSecuritySettingsProvider.notifier).load(),
        throwsA(isA<AuraProfileAccessDenied>()),
      );

      await container.read(profileSessionProvider.notifier).setupPin('1234');
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(
          container.read(profileSessionProvider).privateSessionActive, isTrue);
      expect(container.read(ayushSecuritySettingsProvider).loaded, isTrue);
      expect(container.read(ayushSecuritySettingsProvider).settings.autoLock,
          AyushAutoLock.tenMinutes);
      expect(
          container
              .read(ayushSecuritySettingsProvider)
              .settings
              .backgroundLockGrace,
          AyushBackgroundLockGrace.oneMinute);

      container.read(profileSessionProvider.notifier).lock();
      await Future<void>.delayed(const Duration(milliseconds: 1));
      expect(container.read(ayushSecuritySettingsProvider).settings,
          AyushSecuritySettings.defaults);
      expect(container.read(ayushSecuritySettingsProvider).loaded, isFalse);
    });
  });
}
