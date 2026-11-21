import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';

/// Discovery outcome for one provider in the active workspace.
///
/// Holds only bounded, non-secret model metadata. No prompt, key, response body
/// or credential is ever copied into this state.
enum AiModelLoadStatus {
  idle,
  loading,
  loaded,
  noModels,
  unavailable,
  error,
}

class AiModelCatalogEntry {
  const AiModelCatalogEntry({
    this.status = AiModelLoadStatus.idle,
    this.models = const <AiModelInfo>[],
    this.failureKind,
    this.message,
    this.loadedAt,
  });

  final AiModelLoadStatus status;
  final List<AiModelInfo> models;
  final AiFailureKind? failureKind;
  final String? message;
  final DateTime? loadedAt;

  bool get isLoading => status == AiModelLoadStatus.loading;
  bool get hasModels => models.isNotEmpty;

  /// True for connection-shaped failures where classifying the provider as
  /// merely misconfigured would be misleading.
  bool get isUnavailable => AiProviderManagementMessages.isConnectionFailure(
      failureKind ?? AiFailureKind.unknown);
}

/// Fixed, secret-free messages for provider-management failures.
abstract final class AiProviderManagementMessages {
  static const String configuration =
      'Complete this provider configuration before requesting models.';
  static const String credentials = 'Add an API key for this provider first.';
  static const String unsupported =
      'This provider is not supported on this device.';
  static const String discoveryUnavailable =
      'Model discovery is unavailable for this provider.';
  static const String cancelled = 'The request was cancelled.';
  static const String unknown = 'The provider could not be reached.';
  static const String noModels =
      'The provider is reachable but has no installed models.';
  static const String ollamaOffline =
      'Ollama is not reachable on loopback. Start it and refresh models.';
  static const String ollamaAndroidUnavailable =
      'Local Ollama is not available on Android. Use a cloud provider instead.';
  static const String selectedModelMissing =
      'The selected model is no longer available. Choose a new model.';

  static bool isConnectionFailure(AiFailureKind kind) => switch (kind) {
        AiFailureKind.networkFailure ||
        AiFailureKind.dnsFailure ||
        AiFailureKind.tlsFailure ||
        AiFailureKind.timeout ||
        AiFailureKind.connectionTimeout ||
        AiFailureKind.streamingTimeout ||
        AiFailureKind.providerUnavailable =>
          true,
        _ => false,
      };

  static String forFailure(AiFailureKind kind) => switch (kind) {
        AiFailureKind.configuration ||
        AiFailureKind.needsConfiguration =>
          configuration,
        AiFailureKind.missingCredentials => credentials,
        AiFailureKind.unsupportedProvider => unsupported,
        AiFailureKind.cancelled => cancelled,
        AiFailureKind.authentication ||
        AiFailureKind.permissionDenied =>
          'The provider rejected the credentials.',
        AiFailureKind.rateLimited => 'The provider is rate limiting requests.',
        AiFailureKind.serverError => 'The provider is temporarily unavailable.',
        AiFailureKind.badRequest ||
        AiFailureKind.notFound ||
        AiFailureKind.payloadTooLarge ||
        AiFailureKind.malformedResponse =>
          'The provider returned an unexpected response.',
        _ => unknown,
      };
}
