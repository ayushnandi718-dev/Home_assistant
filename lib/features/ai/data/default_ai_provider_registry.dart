import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_registry.dart';

/// Immutable adapter registry with fail-closed routing.
class DefaultAiProviderRegistry implements AiProviderRegistry {
  DefaultAiProviderRegistry(Iterable<AiProviderAdapter> adapters)
      : _adapters = List<AiProviderAdapter>.unmodifiable(adapters) {
    final Set<AiProviderKind> seen = <AiProviderKind>{};
    for (final AiProviderAdapter adapter in _adapters) {
      for (final AiProviderKind kind in adapter.supportedKinds) {
        if (!seen.add(kind)) {
          throw ArgumentError(
            'More than one AI adapter claims provider kind ${kind.name}.',
          );
        }
      }
    }
  }

  final List<AiProviderAdapter> _adapters;

  @override
  bool supports(AiProviderConfig config) => _adapters.any(
        (AiProviderAdapter adapter) =>
            adapter.supportedKinds.contains(config.kind),
      );

  @override
  AiProviderAdapter adapterFor(AiProviderConfig config) {
    for (final AiProviderAdapter adapter in _adapters) {
      if (adapter.supportedKinds.contains(config.kind)) return adapter;
    }
    throw const AiException(
      AiFailureKind.unsupportedProvider,
      'This AI provider kind is not supported on this device.',
    );
  }

  @override
  List<AiProviderDescriptor> get descriptors => _adapters
      .expand(
        (AiProviderAdapter adapter) => adapter.supportedKinds.map(
          (AiProviderKind kind) => AiProviderDescriptor(
            kind: kind,
            capabilities: adapter.capabilities,
          ),
        ),
      )
      .toList(growable: false);
}
