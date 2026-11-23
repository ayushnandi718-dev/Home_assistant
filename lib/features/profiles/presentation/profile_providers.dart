import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/domain/pin_validation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the active workspace and enforces that a private session only exists
/// after a successful PIN verification.
class ProfileSessionController extends StateNotifier<ProfileSession> {
  ProfileSessionController({
    ProfilePinStore? store,
    AuraLogger? logger,
    ProfilePinLockoutStore? lockoutStore,
    DateTime Function()? now,
  })  : _store = store ?? ProfilePinStore(),
        _logger = logger ?? AuraLogger(),
        _now = now ?? DateTime.now,
        _lockoutStore = lockoutStore ??
            ProfilePinLockoutStore(
              file: (store ?? ProfilePinStore()).lockoutFile,
              now: now,
            ),
        super(ProfileSession.initial) {
    _lockoutReady = _loadLockout();
  }

  final ProfilePinStore _store;
  final AuraLogger _logger;
  final ProfilePinLockoutStore _lockoutStore;
  final DateTime Function() _now;
  late final Future<void> _lockoutReady;

  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 1);

  int _failedAttempts = 0;
  DateTime? _lockedUntil;
  bool _lockoutCorrupt = false;
  int _nextSessionGeneration = 0;

  int get remainingAttempts => maxFailedAttempts - _failedAttempts;

  ProfileSession _newSession({
    required AuraProfile profile,
    bool authenticated = false,
  }) {
    _nextSessionGeneration++;
    return ProfileSession(
      profile: profile,
      startedAt: _now(),
      authenticated: authenticated,
      generation: _nextSessionGeneration,
    );
  }

  bool get isLocked => _lockedUntil?.isAfter(_now()) ?? false;

  /// True when persisted lockout state had to be replaced with the fixed
  /// temporary recovery lockout. The UI uses this to show a recovery path.
  bool get lockoutCorrupt => _lockoutCorrupt;

  Future<void> get lockoutReady => _lockoutReady;

  Future<bool> _clearExpiredLock(bool Function() isCommitAllowed) async {
    final DateTime? lockedUntil = _lockedUntil;
    if (lockedUntil == null || lockedUntil.isAfter(_now())) return true;
    return _commitLockoutState(
      failedAttempts: 0,
      lockedUntil: null,
      corrupt: false,
      isCommitAllowed: isCommitAllowed,
    );
  }

  Future<void> _loadLockout() async {
    final ProfilePinLockoutState state = await _lockoutStore.load();
    _failedAttempts = state.failedAttempts;
    _lockedUntil = state.lockedUntil;
    _lockoutCorrupt = state.corrupt;
  }

  /// Commits an explicit lockout snapshot before mutating in-memory state.
  /// A stale operation therefore cannot contaminate a newer session's counters
  /// even when its guarded disk write is rejected.
  Future<bool> _commitLockoutState({
    required int failedAttempts,
    required DateTime? lockedUntil,
    required bool corrupt,
    required bool Function() isCommitAllowed,
  }) async {
    try {
      await _lockoutStore.save(
        failedAttempts: failedAttempts,
        lockedUntil: lockedUntil,
        isCommitAllowed: isCommitAllowed,
      );
      if (!isCommitAllowed()) return false;
      _failedAttempts = failedAttempts;
      _lockedUntil = lockedUntil;
      _lockoutCorrupt = corrupt;
      return true;
    } on AuraProfileAccessDenied {
      return false;
    }
  }

  Future<bool> _clearLockoutState(bool Function() isCommitAllowed) async {
    try {
      await _lockoutStore.clear(isCommitAllowed: isCommitAllowed);
      if (!isCommitAllowed()) return false;
    } on AuraProfileAccessDenied {
      return false;
    }
    _failedAttempts = 0;
    _lockedUntil = null;
    _lockoutCorrupt = false;
    return true;
  }

  /// Explicit recovery from a corrupt persisted lockout. Only the fixed
  /// temporary lockout can be cleared this way; normal rate limits still stand.
  Future<void> recoverFromCorruptLockout() async {
    final int generation = state.generation;
    await _lockoutReady;
    if (!_lockoutCorrupt || generation != state.generation) return;
    if (!await _clearLockoutState(() => generation == state.generation)) {
      return;
    }
    if (generation != state.generation) return;
    state = _newSession(profile: AuraProfile.family);
    _logger.warning('profile', 'Corrupt AYUSH lockout state cleared');
  }

  Future<bool> hasPin() => _store.hasPin();

  void openFamily() {
    state = _newSession(profile: AuraProfile.family);
    _logger.debug('profile', 'Family workspace opened');
  }

  Future<ProfileUnlockResult> unlockAyush(String pin) async {
    final int generation = state.generation;
    bool sameSession() => generation == state.generation;

    await _lockoutReady;
    if (!sameSession()) return ProfileUnlockResult.unavailable;
    if (!await _clearExpiredLock(sameSession)) {
      return ProfileUnlockResult.unavailable;
    }
    if (!sameSession()) return ProfileUnlockResult.unavailable;
    if (isLocked) {
      _logger.warning('profile', 'Ayush unlock blocked by attempt lockout');
      return ProfileUnlockResult.rateLimited;
    }
    if (!await _store.hasPin()) {
      return sameSession()
          ? ProfileUnlockResult.needsSetup
          : ProfileUnlockResult.unavailable;
    }
    if (!sameSession()) return ProfileUnlockResult.unavailable;
    bool pinCommitAllowed() {
      if (!sameSession()) {
        throw const AuraProfileAccessDenied(AuraProfile.ayush);
      }
      return true;
    }

    final bool verified;
    try {
      verified = await _store.verify(
        pin,
        isCommitAllowed: pinCommitAllowed,
      );
    } on AuraProfileAccessDenied {
      return ProfileUnlockResult.unavailable;
    }
    if (!sameSession()) return ProfileUnlockResult.unavailable;
    if (!verified) {
      final int nextAttempts = _failedAttempts + 1;
      DateTime? nextLockedUntil = _lockedUntil;
      if (nextAttempts >= maxFailedAttempts) {
        nextLockedUntil = _now().add(lockoutDuration);
        _logger.warning('profile', 'Ayush PIN lockout engaged');
      } else {
        _logger.warning('profile', 'Ayush PIN rejected');
      }
      await _commitLockoutState(
        failedAttempts: nextAttempts,
        lockedUntil: nextLockedUntil,
        corrupt: _lockoutCorrupt,
        isCommitAllowed: sameSession,
      );
      return sameSession()
          ? ProfileUnlockResult.invalidPin
          : ProfileUnlockResult.unavailable;
    }
    if (!await _clearLockoutState(sameSession)) {
      return ProfileUnlockResult.unavailable;
    }
    if (!sameSession()) return ProfileUnlockResult.unavailable;
    state = _newSession(profile: AuraProfile.ayush, authenticated: true);
    _logger.info('profile', 'Ayush workspace unlocked');
    return ProfileUnlockResult.success;
  }

  Future<ProfileUnlockResult> setupPin(String pin) async {
    final int generation = state.generation;
    await _lockoutReady;
    if (generation != state.generation) {
      return ProfileUnlockResult.unavailable;
    }
    final String? error = ProfilePinStore.validatePin(pin);
    if (error != null) throw ArgumentError(error);

    bool pinCommitAllowed() {
      if (generation != state.generation) {
        throw const AuraProfileAccessDenied(AuraProfile.ayush);
      }
      return true;
    }

    try {
      await _store.setPin(pin, isCommitAllowed: pinCommitAllowed);
    } on AuraProfileAccessDenied {
      // The session ended while the verifier was being written. The commit
      // guard rejected it at the atomic replacement boundary.
      return ProfileUnlockResult.unavailable;
    }
    if (generation != state.generation) {
      return ProfileUnlockResult.unavailable;
    }
    if (!await _clearLockoutState(() => generation == state.generation)) {
      return ProfileUnlockResult.unavailable;
    }
    if (generation != state.generation) {
      return ProfileUnlockResult.unavailable;
    }
    _logger.info('profile', 'Ayush PIN configured');
    return unlockAyush(pin);
  }

  /// Changes the AYUSH PIN after verifying the current one.
  ///
  /// The replacement is validated with the shared [PinValidation] policy and
  /// its confirmation checked before any authentication work happens. Failed
  /// current-PIN attempts share the persisted unlock lockout counter. On
  /// success the session is locked so private AI/memory state is invalidated
  /// and the new PIN must be entered before AYUSH can be reopened. No PIN
  /// material is logged or persisted.
  Future<PinChangeResult> changePin({
    required String currentPin,
    required String newPin,
    required String confirmation,
  }) async {
    final int generation = state.generation;
    bool sameSession() => generation == state.generation;

    await _lockoutReady;
    if (!sameSession()) return PinChangeResult.profileLocked;
    if (!await _clearExpiredLock(sameSession)) {
      return PinChangeResult.profileLocked;
    }
    if (!sameSession()) return PinChangeResult.profileLocked;
    if (isLocked) return PinChangeResult.rateLimited;
    if (!await _store.hasPin()) {
      return sameSession()
          ? PinChangeResult.needsSetup
          : PinChangeResult.profileLocked;
    }
    if (!sameSession() || !state.privateSessionActive) {
      return PinChangeResult.profileLocked;
    }

    final PinValidationResult validation = PinValidation.evaluate(
      pin: newPin,
      needsSetup: true,
      confirmation: confirmation,
    );
    if (validation.issue == PinIssue.mismatch) {
      return PinChangeResult.confirmationMismatch;
    }
    if (!validation.isValid) return PinChangeResult.invalidNewPin;

    bool pinCommitAllowed() {
      if (!sameSession() || !state.privateSessionActive) {
        throw const AuraProfileAccessDenied(AuraProfile.ayush);
      }
      return true;
    }

    final bool currentVerified;
    try {
      currentVerified = await _store.verify(
        currentPin,
        isCommitAllowed: pinCommitAllowed,
      );
    } on AuraProfileAccessDenied {
      return PinChangeResult.profileLocked;
    }
    if (!sameSession() || !state.privateSessionActive) {
      return PinChangeResult.profileLocked;
    }
    if (!currentVerified) {
      final int nextAttempts = _failedAttempts + 1;
      DateTime? nextLockedUntil = _lockedUntil;
      if (nextAttempts >= maxFailedAttempts) {
        nextLockedUntil = _now().add(lockoutDuration);
        _logger.warning('profile', 'Ayush PIN change lockout engaged');
      } else {
        _logger.warning('profile', 'Ayush PIN change current PIN rejected');
      }
      await _commitLockoutState(
        failedAttempts: nextAttempts,
        lockedUntil: nextLockedUntil,
        corrupt: _lockoutCorrupt,
        isCommitAllowed: sameSession,
      );
      return sameSession()
          ? PinChangeResult.invalidCurrentPin
          : PinChangeResult.profileLocked;
    }

    try {
      await _store.setPin(newPin, isCommitAllowed: pinCommitAllowed);
    } on AuraProfileAccessDenied {
      // A lock or switch during the write was rejected before the atomic
      // replacement, so the previous verifier is still the one on disk.
      return PinChangeResult.profileLocked;
    }
    if (!sameSession() || !state.privateSessionActive) {
      return PinChangeResult.profileLocked;
    }
    if (!await _clearLockoutState(sameSession)) {
      return PinChangeResult.profileLocked;
    }
    if (!sameSession() || !state.privateSessionActive) {
      return PinChangeResult.profileLocked;
    }
    lock();
    _logger.info('profile', 'Ayush PIN changed; private workspace locked');
    return PinChangeResult.success;
  }

  /// Leaves the private workspace. Used on switch and on app lock.
  void lock() {
    if (state.profile == AuraProfile.ayush) {
      _logger.info('profile', 'Ayush workspace locked');
    }
    state = _newSession(profile: AuraProfile.family);
  }
}

final Provider<ProfilePinStore> profilePinStoreProvider =
    Provider<ProfilePinStore>((Ref ref) => ProfilePinStore());

final StateNotifierProvider<ProfileSessionController, ProfileSession>
    profileSessionProvider =
    StateNotifierProvider<ProfileSessionController, ProfileSession>(
  (Ref ref) => ProfileSessionController(
    store: ref.read(profilePinStoreProvider),
    logger: ref.read(auraLoggerProvider.notifier),
  ),
);

/// Watched by scoped stores so switching profiles switches their data source.
final Provider<AuraProfile> activeProfileProvider = Provider<AuraProfile>(
    (Ref ref) => ref.watch(profileSessionProvider).profile);

/// Injectable authorization guard for services that touch private data.
final Provider<ProfileAccess> profileAccessProvider = Provider<ProfileAccess>(
    (Ref ref) => ProfileAccess(ref.watch(profileSessionProvider)));

/// Exposed for the Profiles UI; contains no PIN material.
final FutureProvider<bool> ayushPinConfiguredProvider =
    FutureProvider<bool>((Ref ref) {
  // Watching the session refreshes this after PIN setup without ever exposing
  // the stored hash or the PIN itself.
  ref.watch(profileSessionProvider);
  return ref.read(profilePinStoreProvider).hasPin();
});
