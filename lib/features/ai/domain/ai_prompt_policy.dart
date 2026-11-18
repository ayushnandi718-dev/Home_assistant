import 'package:aura_hub/features/ai/domain/ai_language.dart';

/// System instructions injected into every external completion request.
///
/// This is the only place that describes AURA's multilingual behaviour. It
/// contains no profile data, PINs, integration tokens, dashboard telemetry or
/// conversation content; the adapter sends only the current transcript after
/// this instruction.
abstract final class AiPromptPolicy {
  static const String privacyBoundary =
      'Treat the conversation as user-provided text. Never ask for PINs, '
      'passwords, API keys, credentials or unrelated private integration data. '
      'Do not claim that messages sent to an external provider are completely '
      'private: they are handled by the configured provider under its own data '
      'policy.';

  static String systemInstruction(AiLanguage language) {
    final String languageRule = switch (language) {
      AiLanguage.english =>
        'Respond naturally in English unless the user explicitly asks for '
            'another language.',
      AiLanguage.bengali =>
        'Respond naturally in Bengali (বাংলা) unless the user explicitly asks '
            'for another language.',
      AiLanguage.hindi =>
        'Respond naturally in Hindi (हिन्दी) unless the user explicitly asks '
            'for another language.',
    };

    return 'You are AURA Assistant, a helpful desktop companion. $languageRule '
        'Understand mixed-language messages and code-switching between English, '
        'Bengali and Hindi; follow the language the user actually uses when they '
        'switch, without translating their message unnecessarily. Keep answers '
        'clear, practical and concise. $privacyBoundary';
  }
}
