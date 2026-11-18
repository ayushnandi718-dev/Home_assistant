/// Categories of AI failure that the UI can present without inventing a reply.
enum AiFailureKind {
  configuration,
  needsConfiguration,
  consentRequired,
  missingCredentials,
  unsupportedProvider,
  authentication,
  rateLimited,
  providerUnavailable,
  timeout,
  malformedResponse,
  cancelled,
  unknown,
}

extension AiFailureKindX on AiFailureKind {
  /// Whether retrying the same request can reasonably succeed.
  bool get isRetryable {
    switch (this) {
      case AiFailureKind.rateLimited:
      case AiFailureKind.providerUnavailable:
      case AiFailureKind.timeout:
      case AiFailureKind.unknown:
        return true;
      case AiFailureKind.configuration:
      case AiFailureKind.needsConfiguration:
      case AiFailureKind.consentRequired:
      case AiFailureKind.missingCredentials:
      case AiFailureKind.unsupportedProvider:
      case AiFailureKind.authentication:
      case AiFailureKind.malformedResponse:
      case AiFailureKind.cancelled:
        return false;
    }
  }
}

/// Safe, secret-free AI exception.
///
/// Messages are chosen from fixed strings or status codes. Provider response
/// bodies, headers, keys and transcript content are NEVER copied into an
/// exception, so these values can reach the UI and diagnostic logs safely.
class AiException implements Exception {
  const AiException(
    this.kind,
    this.message, {
    this.statusCode,
  });

  final AiFailureKind kind;
  final String message;
  final int? statusCode;

  @override
  String toString() => 'AiException(${kind.name}): $message';
}

/// Maps an HTTP status to a safe, user-facing AI failure.
AiException aiHttpException(int statusCode) {
  if (statusCode == 401 || statusCode == 403) {
    return const AiException(
      AiFailureKind.authentication,
      'The provider rejected the API key. Check the credential in provider settings.',
    );
  }
  if (statusCode == 429) {
    return const AiException(
      AiFailureKind.rateLimited,
      'The provider rate limit was reached. Wait a moment and try again.',
    );
  }
  if (statusCode >= 500) {
    return AiException(
      AiFailureKind.providerUnavailable,
      'The provider is temporarily unavailable (HTTP $statusCode).',
      statusCode: statusCode,
    );
  }
  return AiException(
    AiFailureKind.unknown,
    'The provider rejected the request (HTTP $statusCode).',
    statusCode: statusCode,
  );
}
