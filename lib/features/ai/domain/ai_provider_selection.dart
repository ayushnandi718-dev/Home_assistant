import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';

/// Shared rules for deciding which provider serves the next AI request.
///
/// This mirrors the chat controller's long-standing selection contract so the
/// chat badge, provider cards and readiness pill cannot disagree. It stores no
/// state of its own: selection remains in profile-scoped [AiPreferences].
abstract final class AiProviderSelection {
  /// Model ids are opaque provider identifiers. Keep them bounded and free of
  /// whitespace/control characters so an invalid value can never reach a
  /// provider request or a saved configuration.
  static const int maxModelIdLength = 200;
  static final RegExp modelIdPattern = RegExp(r'^[A-Za-z0-9._:/+\-]+$');

  /// Returns the config the next request will actually use, or null when no
  /// enabled provider is available.
  ///
  /// An explicit selection is honoured even when it is disabled: in that case
  /// requests stay blocked rather than silently falling back to another
  /// provider. Without an explicit selection the first enabled config is used.
  static AiProviderConfig? effective(
    List<AiProviderConfig> configs,
    AiPreferences preferences,
  ) {
    final String? selectedId = preferences.selectedProviderId;
    final AiProviderConfig? selected =
        selectedId == null ? null : byId(configs, selectedId);
    final AiProviderConfig? effective = selected ??
        (configs.isEmpty
            ? null
            : configs.firstWhere(
                (AiProviderConfig item) => item.enabled,
                orElse: () => configs.first,
              ));
    if (effective == null || !effective.enabled) return null;
    return effective;
  }

  static AiProviderConfig? byId(
    List<AiProviderConfig> configs,
    String? providerId,
  ) {
    if (providerId == null) return null;
    for (final AiProviderConfig config in configs) {
      if (config.id == providerId) return config;
    }
    return null;
  }

  /// Returns a safe, fixed validation message, or null for an acceptable id.
  static String? validateModelId(String? value) {
    final String model = value?.trim() ?? '';
    if (model.isEmpty) return 'Select a model before saving this provider.';
    if (model.length > maxModelIdLength) {
      return 'The model identifier is too long.';
    }
    if (!modelIdPattern.hasMatch(model)) {
      return 'The model identifier contains unsupported characters.';
    }
    return null;
  }

  static bool isValidModelId(String? value) => validateModelId(value) == null;
}
