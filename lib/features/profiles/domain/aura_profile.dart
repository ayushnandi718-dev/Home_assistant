/// The only two workspaces AURA Hub supports.
enum AuraProfile { ayush, family }

extension AuraProfileX on AuraProfile {
  String get label => this == AuraProfile.ayush ? 'AYUSH' : 'FAMILY';

  String get description => this == AuraProfile.ayush
      ? 'Private workspace - PIN required'
      : 'Shared household workspace - opens directly';

  bool get requiresPin => this == AuraProfile.ayush;

  /// Used to namespace persisted data. Family data is never read by Ayush's
  /// private scope and vice versa.
  String get storageScope => name;
}

/// Result of a PIN unlock attempt.
enum ProfileUnlockResult {
  success,
  invalidPin,
  needsSetup,
  rateLimited,
  unavailable,
}

/// Outcome of an authenticated AYUSH PIN change.
///
/// The current PIN must verify before the replacement is written, and all
/// failures share the unlock lockout so the protection cannot be bypassed by
/// switching between the unlock and change forms.
enum PinChangeResult {
  success,
  invalidCurrentPin,
  invalidNewPin,
  confirmationMismatch,
  rateLimited,
  needsSetup,

  /// The private session ended, or the initiating session was replaced, before
  /// the change could be committed. No PIN material is written on this path.
  profileLocked,
}

/// Immutable description of the active workspace session.
class ProfileSession {
  const ProfileSession({
    required this.profile,
    required this.startedAt,
    this.authenticated = false,
    this.generation = 0,
  });

  /// The app always starts in the open Family workspace. A private Ayush
  /// session is never restored automatically after a restart.
  static final ProfileSession initial = ProfileSession(
    profile: AuraProfile.family,
    startedAt: DateTime(1970),
    authenticated: false,
  );

  final AuraProfile profile;
  final DateTime startedAt;
  final bool authenticated;

  /// Monotonic identity for this workspace session. Every open, unlock, lock
  /// and recovery transition advances it so an async operation can prove it is
  /// still operating on the session that authorised it.
  final int generation;

  bool get privateSessionActive =>
      profile == AuraProfile.ayush && authenticated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileSession &&
          other.profile == profile &&
          other.authenticated == authenticated &&
          other.generation == generation;

  @override
  int get hashCode => Object.hash(profile, authenticated, generation);
}

/// Thrown when code tries to read private data without an unlocked session.
class AuraProfileAccessDenied implements Exception {
  const AuraProfileAccessDenied(this.scope);

  final AuraProfile scope;

  @override
  String toString() => 'Private ${scope.label} data is locked.';
}

/// Service-level authorization guard.
///
/// UI visibility is never the security boundary: any service that wants to
/// read private data must go through [requirePrivate].
class ProfileAccess {
  const ProfileAccess(this.session);

  final ProfileSession session;

  bool canRead(AuraProfile scope) =>
      scope == AuraProfile.family || session.privateSessionActive;

  T requirePrivate<T>(AuraProfile scope, T value) {
    if (!canRead(scope)) throw AuraProfileAccessDenied(scope);
    return value;
  }
}

/// Identity of one authorised profile operation across asynchronous work.
///
/// Controllers capture this synchronously before their first await and call
/// [requireCurrent] after every boundary that can publish, persist or clear
/// state. A lock, profile switch or new unlock advances the session generation
/// and makes every older owner stale even when the profile looks identical.
class ProfileOperationOwner {
  ProfileOperationOwner({
    required ProfileAccessReader accessReader,
    required AuraProfile profile,
  })  : _accessReader = accessReader,
        _profile = profile,
        _session = accessReader().session {
    requireCurrent();
  }

  final ProfileAccessReader _accessReader;
  final AuraProfile _profile;
  final ProfileSession _session;

  AuraProfile get profile => _profile;

  int get generation => _session.generation;

  bool get isCurrent {
    final ProfileAccess access = _accessReader();
    final ProfileSession current = access.session;
    return current.profile == _profile &&
        current.generation == _session.generation &&
        access.canRead(_profile);
  }

  /// Fails closed with the existing access-denied error when the initiating
  /// profile session is no longer active or authorised.
  void requireCurrent() {
    if (!isCurrent) throw AuraProfileAccessDenied(_profile);
  }
}

/// Supplies the current access decision at call time.
///
/// Services that outlive a session change must use a reader instead of storing
/// a [ProfileAccess] snapshot, otherwise a locked workspace may stay readable
/// or an unlocked one may stay blocked.
typedef ProfileAccessReader = ProfileAccess Function();
