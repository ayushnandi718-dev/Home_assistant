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
  })  : _store = store ?? ProfilePinStore(),
        _logger = logger ?? AuraLogger(),
        super(ProfileSession.initial);

  final ProfilePinStore _store;
  final AuraLogger _logger;

  /// In-memory throttling. A restart clears the counter; this is a local
  /// convenience lock, not a hardened authentication service.
  static const int maxFailedAttempts = 5;
  static const Duration lockoutDuration = Duration(minutes: 1);

  int _failedAttempts = 0;
  DateTime? _lockedUntil;

  int get remainingAttempts => maxFailedAttempts - _failedAttempts;
  bool get isLocked => _lockedUntil?.isAfter(DateTime.now()) ?? false;

  void _clearExpiredLock() {
    final DateTime? lockedUntil = _lockedUntil;
    if (lockedUntil != null && !lockedUntil.isAfter(DateTime.now())) {
      _lockedUntil = null;
      _failedAttempts = 0;
    }
  }

  Future<bool> hasPin() => _store.hasPin();

  void openFamily() {
    state = ProfileSession(
      profile: AuraProfile.family,
      startedAt: DateTime.now(),
    );
    _logger.debug('profile', 'Family workspace opened');
  }

  Future<ProfileUnlockResult> unlockAyush(String pin) async {
    _clearExpiredLock();
    if (isLocked) {
      _logger.warning('profile', 'Ayush unlock blocked by attempt lockout');
      return ProfileUnlockResult.rateLimited;
    }
    if (!await _store.hasPin()) return ProfileUnlockResult.needsSetup;
    if (!await _store.verify(pin)) {
      _failedAttempts++;
      if (_failedAttempts >= maxFailedAttempts) {
        _lockedUntil = DateTime.now().add(lockoutDuration);
        _logger.warning('profile', 'Ayush PIN lockout engaged');
      } else {
        _logger.warning('profile', 'Ayush PIN rejected');
      }
      return ProfileUnlockResult.invalidPin;
    }
    _failedAttempts = 0;
    _lockedUntil = null;
    state = ProfileSession(
      profile: AuraProfile.ayush,
      startedAt: DateTime.now(),
      authenticated: true,
    );
    _logger.info('profile', 'Ayush workspace unlocked');
    return ProfileUnlockResult.success;
  }

  Future<ProfileUnlockResult> setupPin(String pin) async {
    final String? error = ProfilePinStore.validatePin(pin);
    if (error != null) throw ArgumentError(error);
    _failedAttempts = 0;
    _lockedUntil = null;
    await _store.setPin(pin);
    _logger.info('profile', 'Ayush PIN configured');
    return unlockAyush(pin);
  }

  /// Changes the AYUSH PIN after verifying the current one.
  ///
  /// The replacement is validated with the shared [PinValidation] policy and
  /// its confirmation checked before any authentication work happens. Failed
  /// current-PIN attempts share the unlock lockout counter. On success the
  /// session is locked so private AI/memory state is invalidated and the new PIN
  /// must be entered before AYUSH can be reopened. No PIN material is logged.
  Future<PinChangeResult> changePin({
    required String currentPin,
    required String newPin,
    required String confirmation,
  }) async {
    _clearExpiredLock();
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
        _lockedUntil = DateTime.now().add(lockoutDuration);
        _logger.warning('profile', 'Ayush PIN change lockout engaged');
      } else {
        _logger.warning('profile', 'Ayush PIN change current PIN rejected');
      }
      return PinChangeResult.invalidCurrentPin;
    }

    await _store.setPin(newPin);
    _failedAttempts = 0;
    _lockedUntil = null;
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
