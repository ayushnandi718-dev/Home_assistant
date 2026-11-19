import 'dart:async';

import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/security/presentation/security_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AyushSessionReader = ProfileSession Function();
typedef AyushTimeoutReader = Duration? Function();

/// Single, centralised inactivity monitor for the private AYUSH workspace.
///
/// There is exactly one timer for the whole app. It is armed only while an
/// authenticated AYUSH session is active, so FAMILY can never be locked or
/// interrupted by it. The clock is injectable for deterministic tests.
class AyushAutoLockController {
  AyushAutoLockController({
    required AyushSessionReader sessionReader,
    required AyushTimeoutReader timeoutReader,
    required void Function() lockAyush,
    DateTime Function()? now,
    this.activityThrottle = const Duration(seconds: 1),
  })  : _sessionReader = sessionReader,
        _timeoutReader = timeoutReader,
        _lockAyush = lockAyush,
        _now = now ?? DateTime.now;

  final AyushSessionReader _sessionReader;
  final AyushTimeoutReader _timeoutReader;
  final void Function() _lockAyush;
  final DateTime Function() _now;
  final Duration activityThrottle;

  Timer? _timer;
  DateTime? _lastActivityAt;

  /// Number of times the timeout actually fired and locked AYUSH.
  int lockCount = 0;

  /// Begins monitoring. Safe to call repeatedly; only one timer is ever live.
  void start() {
    if (!_sessionReader().privateSessionActive) return;
    _lastActivityAt ??= _now();
    _arm();
  }

  /// Stops monitoring and forgets the activity timestamp.
  void stop() {
    _cancel();
    _lastActivityAt = null;
  }

  /// Re-arms using the current persisted timeout (call after a settings change).
  void refreshTimeout() {
    if (!_sessionReader().privateSessionActive) return;
    _arm();
  }

  /// Registers a valid user interaction, restarting the countdown.
  ///
  /// Throttled so high-frequency input cannot thrash the timer. Calls made
  /// while FAMILY is active are ignored, keeping FAMILY immune.
  void registerActivity() {
    if (!_sessionReader().privateSessionActive) return;
    final DateTime now = _now();
    final DateTime? last = _lastActivityAt;
    if (last != null &&
        _timer != null &&
        now.difference(last) < activityThrottle) {
      return;
    }
    _lastActivityAt = now;
    _arm();
  }

  /// The app returned from background/suspend: treat it as fresh interaction.
  void onAppResumed() {
    if (_sessionReader().privateSessionActive) registerActivity();
  }

  void _arm() {
    _cancel();
    final Duration? timeout = _timeoutReader();
    if (timeout == null) return; // "Never" is an explicit, valid choice.
    _timer = Timer(timeout, _onTimeout);
  }

  void _onTimeout() {
    _timer = null;
    if (!_sessionReader().privateSessionActive) return;
    _lockAyush();
    lockCount++;
    stop();
  }

  void _cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _cancel();
  }
}

/// Long-lived controller wired to the profile session and encrypted AYUSH
/// security settings. Read once at startup so the monitor is alive for the
/// whole app session; it starts itself whenever AYUSH is unlocked.
final Provider<AyushAutoLockController> ayushAutoLockControllerProvider =
    Provider<AyushAutoLockController>((Ref ref) {
  final AyushAutoLockController controller = AyushAutoLockController(
    sessionReader: () => ref.read(profileSessionProvider),
    timeoutReader: () =>
        ref.read(ayushSecuritySettingsProvider).settings.autoLock.duration,
    lockAyush: () => ref.read(profileSessionProvider.notifier).lock(),
  );

  ref.listen<ProfileSession>(profileSessionProvider, (_, ProfileSession next) {
    if (next.privateSessionActive) {
      // This listener can run before other dependents of profileSessionProvider
      // (including profileAccessProvider) have been rebuilt for the new state.
      // Defer the guarded read so it sees the private session, and re-check in
      // case the user locks again in the meantime. The settings listener below
      // re-arms the timer once the persisted value is available.
      unawaited(Future<void>.delayed(Duration.zero).then((_) async {
        if (!ref.read(profileSessionProvider).privateSessionActive) return;
        await ref.read(ayushSecuritySettingsProvider.notifier).load();
      }));
      controller.start();
    } else {
      controller.stop();
      // Clear decrypted private settings from memory as soon as AYUSH locks.
      ref.read(ayushSecuritySettingsProvider.notifier).clear();
    }
  });

  ref.listen<AyushSecuritySettingsState>(
    ayushSecuritySettingsProvider,
    (_, __) => controller.refreshTimeout(),
  );

  ref.onDispose(controller.dispose);

  if (ref.read(profileSessionProvider).privateSessionActive) {
    controller.start();
  }
  return controller;
});
