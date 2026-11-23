/// Categories of AI failure that the UI can present without inventing a reply.
///
/// New categories are additive: existing kinds are retained so saved UI flows
/// and tests keep their meaning, while transport failures now get a precise
/// category instead of being collapsed into [unknown].
enum AiFailureKind {
  configuration,
  needsConfiguration,
  consentRequired,
  missingCredentials,
  unsupportedProvider,
  badRequest,
  authentication,
  permissionDenied,
  notFound,
  payloadTooLarge,
  rateLimited,
  serverError,
  providerUnavailable,
  networkFailure,
  dnsFailure,
  tlsFailure,
  timeout,
  connectionTimeout,
  streamingTimeout,
  malformedResponse,
  streamInterrupted,
  cancelled,
  unknown,

  /// OS credential-vault or stored-credential failure.
  ///
  /// Distinct from [missingCredentials] and [configuration]: the vault exists
  /// but cannot safely provide, replace or remove a stored secret.
  credentialStorage,
}

/// Point in the request lifecycle where a failure or diagnostic was recorded.
enum AiRequestStage {
  prepare,
  connect,
  headers,
  response,
  stream,
  parse,
  persist,
  complete,
}

extension AiFailureKindX on AiFailureKind {
  /// Whether retrying the same request can reasonably succeed.
  ///
  /// Authentication, configuration and malformed-request failures are never
  /// retried automatically. Transport and provider-capacity failures may be,
  /// and the UI still requires a deliberate user action for chat retries.
  bool get isRetryable {
    switch (this) {
      case AiFailureKind.rateLimited:
      case AiFailureKind.serverError:
      case AiFailureKind.providerUnavailable:
      case AiFailureKind.networkFailure:
      case AiFailureKind.dnsFailure:
      case AiFailureKind.tlsFailure:
      case AiFailureKind.timeout:
      case AiFailureKind.connectionTimeout:
      case AiFailureKind.streamingTimeout:
      case AiFailureKind.streamInterrupted:
      case AiFailureKind.unknown:
        return true;
      case AiFailureKind.configuration:
      case AiFailureKind.needsConfiguration:
      case AiFailureKind.consentRequired:
      case AiFailureKind.missingCredentials:
      case AiFailureKind.unsupportedProvider:
      case AiFailureKind.badRequest:
      case AiFailureKind.authentication:
      case AiFailureKind.permissionDenied:
      case AiFailureKind.notFound:
      case AiFailureKind.payloadTooLarge:
      case AiFailureKind.malformedResponse:
      case AiFailureKind.cancelled:
      case AiFailureKind.credentialStorage:
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
    this.stage,
    this.exceptionType,
    this.durationMs,
  });

  final AiFailureKind kind;
  final String message;
  final int? statusCode;

  /// Structured, non-sensitive diagnostics metadata.
  final AiRequestStage? stage;
  final String? exceptionType;
  final int? durationMs;

  @override
  String toString() => 'AiException(${kind.name}): $message';
}

/// Maps an HTTP status to a safe, user-facing AI failure.
AiException aiHttpException(
  int statusCode, {
  AiRequestStage stage = AiRequestStage.response,
}) {
  final AiException failure = switch (statusCode) {
    401 => const AiException(
        AiFailureKind.authentication,
        'The provider rejected the API key. Check the credential in provider settings.',
      ),
    403 => const AiException(
        AiFailureKind.permissionDenied,
        'The provider denied access. Check the key permissions or plan.',
      ),
    404 => const AiException(
        AiFailureKind.notFound,
        'The endpoint or model was not found. Check the base URL and model id.',
      ),
    413 => const AiException(
        AiFailureKind.payloadTooLarge,
        'The message is too large for this provider. Shorten the conversation.',
      ),
    429 => const AiException(
        AiFailureKind.rateLimited,
        'The provider rate limit was reached. Wait a moment and try again.',
      ),
    >= 500 => const AiException(
        AiFailureKind.serverError,
        'The provider is temporarily unavailable. Try again shortly.',
      ),
    _ => const AiException(
        AiFailureKind.badRequest,
        'The provider rejected the request. Check the model and message settings.',
      ),
  };
  return AiException(
    failure.kind,
    failure.message,
    statusCode: statusCode,
    stage: stage,
  );
}
