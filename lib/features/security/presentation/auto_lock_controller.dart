import 'dart:async';

import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/security/domain/ayush_security_settings.dart';
import 'package:aura_hub/features/security/presentation/security_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

typedef AyushSessionReader = ProfileSession Function();
typedef AyushTimeoutReader = Duration? Function();
typedef AyushBackgroundGraceReader = Duration Function();

/// Single, centralised monitor for the private AYUSH workspace.
///
/// There is exactly one inactivity timer and at most one background-grace
/// timer. Both are armed only while an authenticated AYUSH session is active,
/// so FAMILY can never be locked or interrupted. The background grace is
/// independent of the inactivity setting: even "Never" still locks after the
/// app leaves the foreground. The clock is injectable for deterministic tests.
class AyushAutoLockController {
  AyushAutoLockController({
    required AyushSessionReader sessionReader,
    required AyushTimeoutReader timeoutReader,
    required void Function() lockAyush,
    AyushBackgroundGraceReader? backgroundGraceReader,
    DateTime Function()? now,
    this.activityThrottle = const Duration(seconds: 1),
  })  : _sessionReader = sessionReader,
        _timeoutReader = timeoutReader,
        _backgroundGraceReader = backgroundGraceReader ??
            (() => AyushBackgroundLockGrace.thirtySeconds.duration),
        _lockAyush = lockAyush,
        _now = now ?? DateTime.now;

  final AyushSessionReader _sessionReader;
  final AyushTimeoutReader _timeoutReader;
  final AyushBackgroundGraceReader _backgroundGraceReader;
  final void Function() _lockAyush;
  final DateTime Function() _now;
  final Duration activityThrottle;

  Timer? _timer;
  Timer? _backgroundTimer;
  DateTime? _lastActivityAt;
  DateTime? _backgroundStartedAt;
  Duration? _backgroundGraceAtStart;

  /// Guards against an inactivity timer and a background timer both firing
  /// while the same private session is being torn down.
  bool _lockFired = false;

  /// Number of times the timeout actually fired and locked AYUSH.
  int lockCount = 0;

  /// Begins monitoring. Safe to call repeatedly; only one timer of each kind
  /// is ever live.
  void start() {
    if (!_sessionReader().privateSessionActive) return;
    if (_lastActivityAt == null && _backgroundStartedAt == null) {
      _lockFired = false;
    }
    _lastActivityAt ??= _now();
    _arm();
  }

  /// Stops monitoring and forgets all timestamps.
  void stop() {
    _clearTimers();
    _lastActivityAt = null;
    _backgroundStartedAt = null;
    _backgroundGraceAtStart = null;
    _lockFired = false;
  }

  /// Re-arms using the current persisted inactivity timeout.
  void refreshTimeout() {
    if (!_sessionReader().privateSessionActive || _lockFired) return;
    // Background grace owns the countdown while the app is not foregrounded.
    if (_backgroundStartedAt != null) return;
    _arm();
  }

  /// Applies a changed background grace to an already-running grace period.
  void refreshBackgroundGrace() {
    if (!_sessionReader().privateSessionActive ||
        _lockFired ||
        _backgroundStartedAt == null) {
      return;
    }
    final DateTime startedAt = _backgroundStartedAt!;
    final Duration grace = _backgroundGraceReader();
    final Duration elapsed = _now().difference(startedAt);
    _cancelBackground();
    _backgroundGraceAtStart = grace;
    if (elapsed >= grace) {
      _onBackgroundTimeout();
      return;
    }
    _backgroundTimer = Timer(grace - elapsed, _onBackgroundTimeout);
  }

  /// Registers a valid user interaction, restarting the inactivity countdown.
  ///
  /// Throttled so high-frequency input cannot thrash the timer. Calls made
  /// while FAMILY is active or while background grace is running are ignored.
  void registerActivity() {
    if (!_sessionReader().privateSessionActive || _lockFired) return;
    if (_backgroundStartedAt != null) return;
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

  /// The app left the foreground. Starts the short AYUSH-only grace period and
  /// suspends the inactivity countdown so the two cannot race.
  void onAppBackgrounded() {
    if (!_sessionReader().privateSessionActive || _lockFired) return;
    // Paused, inactive and hidden can arrive in sequence. The first event owns
    // the grace period; later events must not extend it.
    if (_backgroundStartedAt != null) return;
    _backgroundStartedAt = _now();
    _backgroundGraceAtStart = _backgroundGraceReader();
    _cancelIdle();
    _backgroundTimer = Timer(_backgroundGraceAtStart!, _onBackgroundTimeout);
  }

  /// The app returned from background/suspend. Cancels the grace timer and
  /// reconciles against both clocks, locking immediately if either deadline
  /// elapsed while the app was away.
  void onAppResumed() {
    if (!_sessionReader().privateSessionActive || _lockFired) return;
    final DateTime resumedAt = _now();
    final DateTime? startedAt = _backgroundStartedAt;
    if (startedAt == null) {
      registerActivity();
      return;
    }

    final Duration grace = _backgroundGraceAtStart ?? _backgroundGraceReader();
    _cancelBackground();
    _backgroundStartedAt = null;
    _backgroundGraceAtStart = null;

    if (resumedAt.difference(startedAt) >= grace) {
      _triggerLock();
      return;
    }

    _armInactivityRemaining(resumedAt);
  }

  void _arm() {
    _cancelIdle();
    final Duration? timeout = _timeoutReader();
    if (timeout == null) return; // "Never" is an explicit, valid choice.
    _lastActivityAt ??= _now();
    _timer = Timer(timeout, _onIdleTimeout);
  }

  /// Re-arms only the unused portion of the inactivity window after a resume,
  /// so background time cannot extend the deadline from the last real input.
  void _armInactivityRemaining(DateTime at) {
    _cancelIdle();
    final Duration? timeout = _timeoutReader();
    if (timeout == null) return;
    final DateTime lastActivity = _lastActivityAt ?? at;
    final Duration remaining = timeout - at.difference(lastActivity);
    if (remaining <= Duration.zero) {
      _triggerLock();
      return;
    }
    _timer = Timer(remaining, _onIdleTimeout);
  }

  void _onIdleTimeout() {
    _timer = null;
    _triggerLock();
  }

  void _onBackgroundTimeout() {
    _backgroundTimer = null;
    _triggerLock();
  }

  void _triggerLock() {
    if (_lockFired || !_sessionReader().privateSessionActive) return;
    _lockFired = true;
    _clearTimers();
    _lastActivityAt = null;
    _backgroundStartedAt = null;
    _backgroundGraceAtStart = null;
    _lockAyush();
    lockCount++;
  }

  void _clearTimers() {
    _cancelIdle();
    _cancelBackground();
  }

  void _cancelIdle() {
    _timer?.cancel();
    _timer = null;
  }

  void _cancelBackground() {
    _backgroundTimer?.cancel();
    _backgroundTimer = null;
  }

  void dispose() {
    _clearTimers();
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
    backgroundGraceReader: () => ref
        .read(ayushSecuritySettingsProvider)
        .settings
        .backgroundLockGrace
        .duration,
    lockAyush: () => ref.read(profileSessionProvider.notifier).lock(),
  );

  ref.listen<ProfileSession>(profileSessionProvider, (_, ProfileSession next) {
    if (next.privateSessionActive) {
      // This listener can run before other dependents of profileSessionProvider
      // (including profileAccessProvider) have been rebuilt for the new state.
      // Defer the guarded read so it sees the private session, and re-check in
      // case the user locks again in the meantime. The settings listener below
      // re-arms the timers once the persisted values are available.
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
    (_, __) {
      controller.refreshTimeout();
      controller.refreshBackgroundGrace();
    },
  );

  ref.onDispose(controller.dispose);

  if (ref.read(profileSessionProvider).privateSessionActive) {
    controller.start();
  }
  return controller;
});
