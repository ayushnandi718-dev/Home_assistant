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

  /// AURA never uses abusive or derogatory slang, even when the user does.
  static const String respectRule =
      'Keep the conversation respectful. Do not use, repeat or translate '
      'abusive, vulgar or derogatory slang into any language.';

  /// Language behaviour that applies regardless of the configured preference.
  ///
  /// The user never has to pick a language for AURA to understand them. The
  /// model follows the language and script of the message it receives, and the
  /// configured value is only a tie-breaker when that is genuinely unclear.
  static const String languageMirrorRule =
      'Mirror the language and script the user actually writes in. This '
      'includes Hinglish (Hindi written in Latin script), Bengali (বাংলা) '
      'written in Latin script, Hindi (हिन्दी) in Devanagari, Bengali in Bengali '
      'script, and natural code-switching between English, Hindi and Bengali. '
      'Never translate the user’s message or switch language unless they '
      'explicitly ask you to.';

  static String systemInstruction(AiLanguage language) {
    final String languageRule = switch (language) {
      AiLanguage.auto =>
        'Detect the language or mix of the user’s latest message and reply in '
            'that same language or mix.',
      AiLanguage.english =>
        'Use English when the user’s language is genuinely unclear.',
      AiLanguage.hindi =>
        'Prefer Hindi when the user’s language is genuinely unclear.',
      AiLanguage.bengali =>
        'Prefer Bengali when the user’s language is genuinely unclear.',
    };

    return 'You are AURA Assistant, a helpful desktop companion. $languageRule '
        '$languageMirrorRule '
        'Understand mixed-language messages and code-switching, and follow the '
        'language the user actually uses when they switch. Keep answers clear, '
        'practical and concise. $respectRule $privacyBoundary';
  }
}
