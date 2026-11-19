import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';

/// Non-secret description of a provider kind supported by the app.
class AiProviderDescriptor {
  const AiProviderDescriptor({
    required this.kind,
    required this.capabilities,
  });

  final AiProviderKind kind;
  final AiProviderCapabilities capabilities;

  String get label => kind.label;
  String get description => kind.description;
}

/// Selects the adapter that serves a provider configuration.
///
/// The registry is intentionally profile-agnostic. Profile access, consent and
/// credential resolution remain in the controllers that surround it.
abstract class AiProviderRegistry {
  const AiProviderRegistry();

  /// True when an adapter is registered for this configuration's kind.
  bool supports(AiProviderConfig config);

  /// Returns the adapter for [config] or fails closed.
  AiProviderAdapter adapterFor(AiProviderConfig config);

  /// Honest capability summary for informational UI; contains no secrets.
  List<AiProviderDescriptor> get descriptors;
}
