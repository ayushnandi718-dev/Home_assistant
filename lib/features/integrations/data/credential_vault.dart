import 'package:aura_hub/features/integrations/domain/integration_service.dart';

/// OS-backed secret storage boundary used by integration token stores.
///
/// Implementations must keep secrets out of plain JSON, source, logs and
/// diagnostics. This abstraction exists so tests can use an in-memory fake and
/// never call a real credential API.
abstract class CredentialVault {
  Future<void> write({required String target, required String secret});

  Future<String?> read({required String target});

  Future<bool> delete({required String target});
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
