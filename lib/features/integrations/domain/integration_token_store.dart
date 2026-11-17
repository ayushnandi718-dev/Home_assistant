import 'package:aura_hub/features/integrations/domain/integration_service.dart';

/// Thrown when integration/credential work is attempted before a real secure
/// backend exists. Never swallow this into a "disconnected" UI state.
class IntegrationUnavailable implements Exception {
  const IntegrationUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Boundary for OAuth/API credentials.
///
/// Implementations MUST use an OS keystore/encrypted backend. No token or
/// secret may be written to plain JSON, Flutter source, logs or diagnostics.
/// No implementation is provided in this milestone.
abstract class IntegrationTokenStore {
  Future<bool> hasToken({
    required IntegrationService service,
    required String storageScope,
  });

  /// Returns an opaque reference/handle, never the raw secret itself.
  Future<String> storeToken({
    required IntegrationService service,
    required String storageScope,
    required String tokenReference,
  });

  Future<void> deleteToken({
    required IntegrationService service,
    required String storageScope,
  });
}

/// OAuth hand-off boundary. A real implementation must open a system browser /
/// App Links flow and return only an authorization code or callback payload to
/// a secure backend; it must never embed client secrets in this app.
abstract class IntegrationOAuthFlow {
  Future<String> beginAuthorization({
    required IntegrationService service,
    required List<String> scopes,
  });
}

/// Health contract for a real integration adapter.
abstract class IntegrationClient {
  IntegrationService get service;

  Future<bool> isAvailable();
}
