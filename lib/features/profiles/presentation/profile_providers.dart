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

  int get remainingAttempts => maxFailedAttempts - _failedAttempts;

  bool get isLocked => _lockedUntil?.isAfter(_now()) ?? false;

  /// True when persisted lockout state had to be replaced with the fixed
  /// temporary recovery lockout. The UI uses this to show a recovery path.
  bool get lockoutCorrupt => _lockoutCorrupt;

  Future<void> get lockoutReady => _lockoutReady;

  bool _clearExpiredLock() {
    final DateTime? lockedUntil = _lockedUntil;
    if (lockedUntil != null && !lockedUntil.isAfter(_now())) {
      _lockedUntil = null;
      _failedAttempts = 0;
      _lockoutCorrupt = false;
      return true;
    }
    return false;
  }

  Future<void> _loadLockout() async {
    final ProfilePinLockoutState state = await _lockoutStore.load();
    _failedAttempts = state.failedAttempts;
    _lockedUntil = state.lockedUntil;
    _lockoutCorrupt = state.corrupt;
  }

  Future<void> _persistLockout() => _lockoutStore.save(
        failedAttempts: _failedAttempts,
        lockedUntil: _lockedUntil,
      );

  Future<void> _clearLockoutState() async {
    _failedAttempts = 0;
    _lockedUntil = null;
    _lockoutCorrupt = false;
    await _lockoutStore.clear();
  }

  /// Explicit recovery from a corrupt persisted lockout. Only the fixed
  /// temporary lockout can be cleared this way; normal rate limits still stand.
  Future<void> recoverFromCorruptLockout() async {
    await _lockoutReady;
    if (!_lockoutCorrupt) return;
    await _clearLockoutState();
    state = ProfileSession.initial;
    _logger.warning('profile', 'Corrupt AYUSH lockout state cleared');
  }

  Future<bool> hasPin() => _store.hasPin();

  void openFamily() {
    state = ProfileSession(
      profile: AuraProfile.family,
      startedAt: _now(),
    );
    _logger.debug('profile', 'Family workspace opened');
  }

  Future<ProfileUnlockResult> unlockAyush(String pin) async {
    await _lockoutReady;
    if (_clearExpiredLock()) await _persistLockout();
    if (isLocked) {
      _logger.warning('profile', 'Ayush unlock blocked by attempt lockout');
      return ProfileUnlockResult.rateLimited;
    }
    if (!await _store.hasPin()) return ProfileUnlockResult.needsSetup;
    if (!await _store.verify(pin)) {
      _failedAttempts++;
      if (_failedAttempts >= maxFailedAttempts) {
        _lockedUntil = _now().add(lockoutDuration);
        _logger.warning('profile', 'Ayush PIN lockout engaged');
      } else {
        _logger.warning('profile', 'Ayush PIN rejected');
      }
      await _persistLockout();
      return ProfileUnlockResult.invalidPin;
    }
    await _clearLockoutState();
    state = ProfileSession(
      profile: AuraProfile.ayush,
      startedAt: _now(),
      authenticated: true,
    );
    _logger.info('profile', 'Ayush workspace unlocked');
    return ProfileUnlockResult.success;
  }

  Future<ProfileUnlockResult> setupPin(String pin) async {
    await _lockoutReady;
    final String? error = ProfilePinStore.validatePin(pin);
    if (error != null) throw ArgumentError(error);
    await _store.setPin(pin);
    await _clearLockoutState();
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
    await _lockoutReady;
    if (_clearExpiredLock()) await _persistLockout();
    if (isLocked) return PinChangeResult.rateLimited;
    if (!await _store.hasPin()) return PinChangeResult.needsSetup;

    final PinValidationResult validation = PinValidation.evaluate(
      pin: newPin,
      needsSetup: true,
      confirmation: confirmation,
    );
    if (validation.issue == PinIssue.mismatch) {
      return PinChangeResult.confirmationMismatch;
    }
    if (!validation.isValid) return PinChangeResult.invalidNewPin;

    if (!await _store.verify(currentPin)) {
      _failedAttempts++;
      if (_failedAttempts >= maxFailedAttempts) {
        _lockedUntil = _now().add(lockoutDuration);
        _logger.warning('profile', 'Ayush PIN change lockout engaged');
      } else {
        _logger.warning('profile', 'Ayush PIN change current PIN rejected');
      }
      await _persistLockout();
      return PinChangeResult.invalidCurrentPin;
    }

    await _store.setPin(newPin);
    await _clearLockoutState();
    lock();
    _logger.info('profile', 'Ayush PIN changed; private workspace locked');
    return PinChangeResult.success;
  }

  /// Leaves the private workspace. Used on switch and on app lock.
  void lock() {
    if (state.profile == AuraProfile.ayush) {
      _logger.info('profile', 'Ayush workspace locked');
    }
    state = ProfileSession.initial;
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
