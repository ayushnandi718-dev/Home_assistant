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
}

/// Immutable description of the active workspace session.
class ProfileSession {
  const ProfileSession({
    required this.profile,
    required this.startedAt,
    this.authenticated = false,
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

  bool get privateSessionActive =>
      profile == AuraProfile.ayush && authenticated;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProfileSession &&
          other.profile == profile &&
          other.authenticated == authenticated;

  @override
  int get hashCode => Object.hash(profile, authenticated);
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
