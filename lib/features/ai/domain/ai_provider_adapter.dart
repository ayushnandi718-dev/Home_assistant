import 'package:aura_hub/features/ai/domain/ai_client.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_request_context.dart';

/// Capabilities an adapter can honestly perform.
///
/// These are declarations, not promises that a particular endpoint is online.
/// Connection tests and model discovery still make real provider requests.
class AiProviderCapabilities {
  const AiProviderCapabilities({
    required this.streaming,
    required this.modelDiscovery,
    required this.connectionTest,
  });

  final bool streaming;
  final bool modelDiscovery;
  final bool connectionTest;
}

/// Safe, bounded metadata returned by model discovery.
///
/// Only fields needed for selection are retained. Raw provider payloads,
/// response headers and credentials are never copied into this model.
class AiModelInfo {
  const AiModelInfo({
    required this.id,
    required this.label,
    this.identifier,
    this.sizeBytes,
    this.modifiedAt,
    this.digest,
    this.contextWindow,
    this.ownedBy,
  });

  /// Model id used in chat requests.
  final String id;

  /// Human-readable name supplied by the provider.
  final String label;

  /// Provider-native identifier when it differs from the chat model id.
  final String? identifier;

  final int? sizeBytes;
  final DateTime? modifiedAt;
  final String? digest;
  final int? contextWindow;
  final String? ownedBy;

  @override
  String toString() => 'AiModelInfo($id)';
}

/// Provider-specific implementation of the shared [AiClient] contract.
///
/// Adapters must throw [AiException] with a content-free message on every
/// failure. Credentials arrive only through [AiRequestContext] and are never
/// stored in [AiProviderConfig], diagnostics, or model metadata.
abstract class AiProviderAdapter implements AiClient {
  const AiProviderAdapter();

  /// Provider kinds this adapter can serve.
  Set<AiProviderKind> get supportedKinds;

  /// Capabilities available through this adapter.
  AiProviderCapabilities get capabilities;

  /// Returns discovered model metadata without sending conversation content.
  Future<List<AiModelInfo>> listModels({
    required AiProviderConfig config,
    AiRequestContext? context,
  });
}
