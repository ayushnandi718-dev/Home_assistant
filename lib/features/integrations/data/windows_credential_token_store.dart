import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/integrations/data/windows_credential_vault.dart';
import 'package:aura_hub/features/integrations/domain/integration_service.dart';
import 'package:aura_hub/features/integrations/domain/integration_token_store.dart';

/// Integration token store backed by an OS credential vault.
///
/// The public API still returns an opaque handle; that handle is the credential
/// TARGET NAME, never the secret. Tests inject a fake [CredentialVault] so no
/// real credential API is touched.
class WindowsCredentialTokenStore implements IntegrationTokenStore {
  WindowsCredentialTokenStore({CredentialVault? vault})
      : _vault = vault ?? WindowsCredentialVault();

  final CredentialVault _vault;

  @override
  Future<bool> hasToken({
    required IntegrationService service,
    required String storageScope,
  }) async {
    final String target = credentialTarget(service, storageScope);
    final String? stored = await _vault.read(target: target);
    return stored != null;
  }

  @override
  Future<String> storeToken({
    required IntegrationService service,
    required String storageScope,
    required String tokenReference,
  }) async {
    final String target = credentialTarget(service, storageScope);
    await _vault.write(target: target, secret: tokenReference);
    return target;
  }

  @override
  Future<void> deleteToken({
    required IntegrationService service,
    required String storageScope,
  }) async {
    final String target = credentialTarget(service, storageScope);
    await _vault.delete(target: target);
  }
}
