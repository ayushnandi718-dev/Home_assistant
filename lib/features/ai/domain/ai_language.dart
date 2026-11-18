/// Languages the AI foundation is designed to support.
///
/// This is an interface-level declaration only. No model is contacted and no
/// generated or translated content is produced anywhere in this build.
enum AiLanguage {
  /// No fixed language. The model detects the language or mix the user writes
  /// in (English, Hindi, Hinglish, Bengali or any code-switched combination).
  auto('auto', 'Auto (detect)'),
  english('en', 'English'),
  hindi('hi', 'Hindi'),
  bengali('bn', 'Bengali');

  const AiLanguage(this.code, this.label);

  /// Short language code used in configuration and request payloads.
  final String code;

  /// Human-readable label shown in the UI.
  final String label;

  /// Safely parses a code, returning null when it is not a supported language.
  ///
  /// Parsing is case-insensitive and tolerates surrounding whitespace.
  static AiLanguage? tryParse(String? code) {
    final String? normalised = code?.trim().toLowerCase();
    if (normalised == null || normalised.isEmpty) return null;
    for (final AiLanguage language in AiLanguage.values) {
      if (language.code == normalised) return language;
    }
    return null;
  }

  /// Parses a code with a safe fallback to [AiLanguage.auto].
  static AiLanguage fromCode(String? code) => tryParse(code) ?? AiLanguage.auto;
}
