import 'package:aura_hub/features/integrations/domain/integration_service.dart';

/// Secret-free classification of an OS credential-vault failure.
///
/// These values never carry a secret, raw exception message, header or path.
/// They exist so callers can distinguish a genuinely absent credential from a
/// vault that is unavailable, corrupt, denied or failing mid-operation.
enum CredentialVaultFailure {
  unavailable,
  permissionDenied,
  corruptData,
  readFailure,
  writeFailure,
  deleteFailure,
  platformFailure,
}

/// Common contract for typed vault failures safe to cross layer boundaries.
abstract interface class CredentialVaultError implements Exception {
  CredentialVaultFailure get failure;

  /// Fixed, actionable text safe for UI, diagnostics and logs.
  String get safeMessage;
}

/// OS-backed secret storage boundary used by integration token stores.
///
/// Implementations must keep secrets out of plain JSON, source, logs and
/// diagnostics. This abstraction exists so tests can use an in-memory fake and
/// never call a real credential API.
abstract class CredentialVault {
  /// Writes [secret] to [target].
  ///
  /// [isCommitAllowed] is the final ownership boundary. Implementations MUST
  /// call it synchronously immediately before the platform write, with no
  /// intervening `await`. If it throws or returns `false`, the implementation
  /// MUST make no mutation and MUST throw a typed vault failure. Because the
  /// Windows implementation calls the native API synchronously after this
  /// check, no Dart event (including a lock or profile switch) can interleave
  /// between the final validation and the commit.
  Future<void> write({
    required String target,
    required String secret,
    bool Function()? isCommitAllowed,
  });

  Future<String?> read({required String target});

  /// Removes [target].
  ///
  /// [isCommitAllowed] has the same synchronous commit-boundary contract as
  /// [write]. This prevents a stale delete from removing a credential after its
  /// authorising session has ended or been replaced.
  Future<bool> delete({
    required String target,
    bool Function()? isCommitAllowed,
  });
}

/// Enforces the shared commit-boundary contract for vault implementations.
///
/// Call this immediately before the native mutation. A guard that throws (for
/// example an `AuraProfileAccessDenied` from the credential store) propagates
/// unchanged; a guard that simply returns `false` becomes a safe typed failure.
void enforceCredentialCommit({
  bool Function()? isCommitAllowed,
  required CredentialVaultFailure failure,
}) {
  if (isCommitAllowed == null) return;
  if (!isCommitAllowed()) throw CredentialVaultException(failure);
}

/// Thrown when secret storage is attempted on a build with no supported vault.
class CredentialStorageUnavailable implements CredentialVaultError {
  const CredentialStorageUnavailable();

  static const String message =
      'Secure credential storage is unavailable on this device. '
      'Windows Credential Manager is supported only in Windows desktop builds.';

  @override
  CredentialVaultFailure get failure => CredentialVaultFailure.unavailable;

  @override
  String get safeMessage => message;

  @override
  String toString() => message;
}

/// Typed failure raised by vault implementations themselves.
///
/// [detail] may contain a non-sensitive platform code or symbol name for
/// debugging. It is deliberately excluded from [safeMessage] and [toString].
class CredentialVaultException implements CredentialVaultError {
  const CredentialVaultException(
    this.failure, {
    this.detail,
  });

  @override
  final CredentialVaultFailure failure;

  /// Non-sensitive technical detail, such as a Win32 error code.
  final String? detail;

  @override
  String get safeMessage => switch (failure) {
        CredentialVaultFailure.unavailable =>
          CredentialStorageUnavailable.message,
        CredentialVaultFailure.permissionDenied =>
          'The device denied access to secure credential storage. '
              'Check device permissions and try again.',
        CredentialVaultFailure.corruptData =>
          'Stored credentials could not be read. '
              'Re-enter the API key to replace them.',
        CredentialVaultFailure.readFailure =>
          'Stored credentials could not be read. Try again.',
        CredentialVaultFailure.writeFailure =>
          'The API key could not be saved. Try again.',
        CredentialVaultFailure.deleteFailure =>
          'The API key could not be removed. It may still be stored on this device.',
        CredentialVaultFailure.platformFailure =>
          'Secure credential storage is unavailable. '
              'Check that the device vault is enabled.',
      };

  @override
  String toString() => 'CredentialVaultException(${failure.name})';
}

/// Fail-closed vault for platforms without a supported secure backend.
///
/// Reads report "nothing stored" and deletes are harmless no-ops so UI refresh
/// paths cannot fail, while writes throw before any secret leaves the caller.
class UnavailableCredentialVault implements CredentialVault {
  const UnavailableCredentialVault();

  @override
  Future<void> write({
    required String target,
    required String secret,
    bool Function()? isCommitAllowed,
  }) async {
    throw const CredentialStorageUnavailable();
  }

  @override
  Future<String?> read({required String target}) async => null;

  @override
  Future<bool> delete({
    required String target,
    bool Function()? isCommitAllowed,
  }) async =>
      false;
}

/// Builds the stable Windows Credential Manager target name for a service and
/// storage scope.
///
/// The returned target has the form `AURA_HUB/<scope>/<SERVICE_NAME>`. It is
/// derived only from the service enum and the caller-supplied scope; the token
/// or secret is NEVER part of the target name, so this value is safe to use in
/// logs or diagnostics (though callers should still avoid logging it).
///
/// [storageScope] is sanitised: any character that is not an ASCII letter,
/// digit, hyphen or underscore is replaced with `_`. That prevents separator
/// (`/`) injection, newline injection and any other control characters from
/// changing the structure of the target name. An empty or fully invalid scope
/// falls back to `default`.
String credentialTarget(IntegrationService service, String storageScope) {
  final String scope = sanitizeCredentialPart(storageScope);
  return 'AURA_HUB/$scope/${service.name}';
}

/// Sanitises one credential-target segment.
///
/// Shared with AI credentials so provider ids and profile scopes cannot inject
/// separators, newlines or control characters into an OS credential target.
/// The secret itself is never part of a target.
String sanitizeCredentialPart(String value, {String fallback = 'default'}) {
  final StringBuffer cleaned = StringBuffer();
  for (int index = 0; index < value.length; index++) {
    final int unit = value.codeUnitAt(index);
    final bool isLetter =
        (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);
    final bool isDigit = unit >= 0x30 && unit <= 0x39;
    final bool isSafeSymbol = unit == 0x2D || unit == 0x5F; // '-' or '_'
    if (isLetter || isDigit || isSafeSymbol) {
      cleaned.write(String.fromCharCode(unit));
    } else {
      cleaned.write('_');
    }
  }
  final String result = cleaned.toString();
  return result.isEmpty ? fallback : result;
}

/// Builds a stable, profile-isolated credential target for an AI provider.
///
/// Format: `AURA_HUB/AI/<profileScope>/<providerId>`. Only sanitised identifiers
/// are included, never a key, prompt or transcript value.
String aiCredentialTarget({
  required String profileScope,
  required String providerId,
}) {
  return 'AURA_HUB/AI/${sanitizeCredentialPart(profileScope)}/${sanitizeCredentialPart(providerId, fallback: 'provider')}';
}
