import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/integrations/data/windows_credential_vault.dart';

/// OS-backed storage for AI provider API keys.
///
/// This is the only AURA AI component allowed to obtain a raw key, and only so
/// it can hand it to the provider adapter for the lifetime of one request. Keys
/// are never written to JSON, logs, diagnostics, Riverpod state or UI models.
/// The Windows implementation uses Credential Manager through the existing
/// [CredentialVault] boundary; other platforms can inject another vault later.
class AiCredentialStore {
  AiCredentialStore({CredentialVault? vault})
      : _vault = vault ?? WindowsCredentialVault();

  final CredentialVault _vault;

  String targetFor({
    required String profileScope,
    required String providerId,
  }) {
    return aiCredentialTarget(
      profileScope: profileScope,
      providerId: providerId,
    );
  }

  Future<bool> has({
    required String profileScope,
    required String providerId,
  }) async {
    final String? stored = await _vault.read(
      target: targetFor(profileScope: profileScope, providerId: providerId),
    );
    return stored != null && stored.trim().isNotEmpty;
  }

  /// Replaces any existing key for this profile/provider pair.
  ///
  /// The key is sent straight to the OS vault. The returned value is an opaque
  /// target name suitable for diagnostics; it is not the key.
  Future<String> save({
    required String profileScope,
    required String providerId,
    required String apiKey,
  }) async {
    final String secret = apiKey.trim();
    if (secret.isEmpty) {
      throw ArgumentError('API key must not be empty.');
    }
    final String target =
        targetFor(profileScope: profileScope, providerId: providerId);
    await _vault.write(target: target, secret: secret);
    // Return the target only: callers must never echo the secret.
    return target;
  }

  /// Internal request-time secret resolution.
  ///
  /// Callers MUST keep the result transient and MUST NOT log, persist or expose
  /// it through Riverpod state or error messages.
  Future<String?> readSecret({
    required String profileScope,
    required String providerId,
  }) async {
    final String? stored = await _vault.read(
      target: targetFor(profileScope: profileScope, providerId: providerId),
    );
    final String? trimmed = stored?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  Future<void> delete({
    required String profileScope,
    required String providerId,
  }) async {
    await _vault.delete(
      target: targetFor(profileScope: profileScope, providerId: providerId),
    );
  }
}
