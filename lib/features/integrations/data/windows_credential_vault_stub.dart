import 'package:aura_hub/features/integrations/data/credential_vault.dart';
import 'package:aura_hub/features/memory/data/native_memory_guard.dart';

/// Web-safe stand-in for the Windows Credential Manager vault.
///
/// It never stores a secret and always fails closed; the Windows implementation
/// remains the only OS-backed vault in native builds.
class WindowsCredentialVault implements CredentialVault {
  const WindowsCredentialVault({NativeMemoryGuard? memoryGuard});

  static const String unavailableMessage =
      'Windows Credential Manager is unavailable in the browser.';

  @override
  Future<void> write({required String target, required String secret}) async {
    throw StateError(unavailableMessage);
  }

  @override
  Future<String?> read({required String target}) async {
    throw StateError(unavailableMessage);
  }

  @override
  Future<bool> delete({required String target}) async {
    throw StateError(unavailableMessage);
  }
}
