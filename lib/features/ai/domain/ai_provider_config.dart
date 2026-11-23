import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/loopback_host.dart';

/// Kinds of provider the AI foundation is designed around.
///
/// OpenAI-compatible endpoints (including Groq) use the OpenAI-compatible
/// adapter. Local Ollama uses its own native adapter. Google Gemini remains a
/// declared future kind and is rejected explicitly rather than approximated.
enum AiProviderKind {
  openAiCompatible,
  googleGemini,
  localOllama;

  /// Display label for informational UI cards.
  String get label {
    switch (this) {
      case AiProviderKind.openAiCompatible:
        return 'OpenAI-compatible endpoint';
      case AiProviderKind.googleGemini:
        return 'Google Gemini';
      case AiProviderKind.localOllama:
        return 'Local Ollama';
    }
  }

  /// Short, honest description of what the category is intended for.
  String get description {
    switch (this) {
      case AiProviderKind.openAiCompatible:
        return 'A user-supplied endpoint speaking an OpenAI-style API.';
      case AiProviderKind.googleGemini:
        return 'Google Gemini models through a future official adapter.';
      case AiProviderKind.localOllama:
        return 'A model running locally, reachable only on loopback.';
    }
  }
}

/// Non-secret configuration for one AI provider.
///
/// SECURITY: this model deliberately has NO field for an API key, token or any
/// other secret. Credentials are resolved at request time from OS secure
/// storage and must never be stored in this model, in the JSON produced by
/// [toJson], or in application logs.
class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.label,
    required this.kind,
    required this.baseUrl,
    required this.model,
    this.enabled = false,
    this.language = AiLanguage.auto,
  });

  /// Capability description retained from the foundation contract. Streaming
  /// is active through the adapter; tools remain declaration-only.
  static const String capabilities =
      'streaming + structured tools (interface only)';

  final String id;
  final String label;
  final AiProviderKind kind;
  final String baseUrl;
  final String model;
  final bool enabled;
  final AiLanguage language;

  /// True when this provider is meant to run on the local machine.
  bool get isLocal => kind == AiProviderKind.localOllama;

  /// True when the basic shape of this config is valid.
  bool get isValid => validate() == null;

  AiProviderConfig copyWith({
    String? id,
    String? label,
    AiProviderKind? kind,
    String? baseUrl,
    String? model,
    bool? enabled,
    AiLanguage? language,
  }) {
    return AiProviderConfig(
      id: id ?? this.id,
      label: label ?? this.label,
      kind: kind ?? this.kind,
      baseUrl: baseUrl ?? this.baseUrl,
      model: model ?? this.model,
      enabled: enabled ?? this.enabled,
      language: language ?? this.language,
    );
  }

  /// Returns a human-readable validation error, or null when valid.
  ///
  /// A URL must use https, or http only when the host is a loopback address.
  /// Plain http to an arbitrary host is rejected so configuration cannot
  /// silently send data in the clear.
  String? validate() {
    final String? endpointError = validateEndpoint();
    if (endpointError != null) return endpointError;
    if (model.trim().isEmpty) return 'Model must not be empty.';
    return null;
  }

  /// Validates everything except the model identifier.
  ///
  /// Model discovery and availability probes legitimately run before a model
  /// has been chosen (a newly installed Ollama has no selected model yet), so
  /// they validate the endpoint without demanding a chat-ready model.
  String? validateEndpoint() {
    if (id.trim().isEmpty) return 'Provider id must not be empty.';
    if (label.trim().isEmpty) return 'Provider label must not be empty.';

    final Uri? uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      return 'Base URL must be an absolute URL.';
    }
    final String scheme = uri.scheme.toLowerCase();
    if (scheme == 'https') return null;
    if (scheme == 'http' && LoopbackHost.isLoopback(uri.host)) return null;
    return 'Base URL must use https, or http only on a loopback host.';
  }

  /// Serialises only non-secret fields. No key, token or secret is emitted.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'label': label,
        'kind': kind.name,
        'baseUrl': baseUrl,
        'model': model,
        'enabled': enabled,
        'language': language.code,
      };

  factory AiProviderConfig.fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Provider config id is missing.');
    }
    // Fail closed: an unknown, missing or malformed kind must never be
    // reinterpreted as another provider. AiConfigStore.load catches this
    // FormatException and skips only the offending record, leaving the
    // persisted file untouched.
    final Object? kindValue = json['kind'];
    AiProviderKind? kind;
    if (kindValue is String) {
      for (final AiProviderKind item in AiProviderKind.values) {
        if (item.name == kindValue) {
          kind = item;
          break;
        }
      }
    }
    if (kind == null) {
      throw const FormatException('Provider config kind is unknown.');
    }
    return AiProviderConfig(
      id: id,
      label: (json['label'] as String?) ?? id,
      kind: kind,
      baseUrl: (json['baseUrl'] as String?) ?? '',
      model: (json['model'] as String?) ?? '',
      enabled: json['enabled'] == true,
      language:
          AiLanguage.tryParse(json['language'] as String?) ?? AiLanguage.auto,
    );
  }
}
