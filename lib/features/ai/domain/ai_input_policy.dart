/// Local, deterministic guardrails for text the user sends to AURA.
///
/// This is deliberately conservative: it blocks well-known abusive or vulgar
/// slang in English and Hinglish before anything is persisted or sent to a
/// provider. Ordinary questions, medical terms and regional languages are not
/// affected. The matcher never logs or returns the matched word to the UI.
abstract final class AiInputPolicy {
  /// Fixed, user-facing message. It contains no user text.
  static const String blockedMessage =
      'Please keep AURA respectful — abusive or slang language is not allowed. '
      'Rephrase your message and try again.';

  /// Common profanity, slurs and abusive Hinglish/Hindi slang.
  ///
  /// Matching is on whole normalised tokens, so words such as "class",
  /// "assistant" or "Gandhi" are not falsely blocked.
  static const Set<String> blockedTokens = <String>{
    // English
    'fuck',
    'fucked',
    'fucker',
    'fucking',
    'shit',
    'shitty',
    'bitch',
    'bitches',
    'bastard',
    'asshole',
    'dickhead',
    'cunt',
    'nigger',
    'nigga',
    'faggot',
    'whore',
    'slut',
    'motherfucker',
    // Hinglish / Hindi abusive slang
    'chutiya',
    'chut',
    'loda',
    'lodu',
    'bhenchod',
    'behnchod',
    'madarchod',
    'gaand',
    'gand',
    'harami',
    'kamina',
    'bhadwa',
    'randi',
    'jhatu',
  };

  /// Multi-word abuse that whole-token matching would miss.
  static const Set<String> blockedPhrases = <String>{
    'maa ki chut',
    'mother fucker',
  };

  /// Returns true when [text] contains blocked abusive or slang language.
  static bool isBlocked(String text) => findBlockedTerm(text) != null;

  /// Internal helper used by tests and the chat controller.
  ///
  /// Returns the category label, never the original user text.
  static String? findBlockedTerm(String text) {
    final String normalised = _normalise(text);
    if (normalised.isEmpty) return null;

    final String padded = ' $normalised ';
    for (final String phrase in blockedPhrases) {
      if (padded.contains(' $phrase ')) return 'abusive phrase';
    }

    for (final String token in _tokens(normalised)) {
      if (blockedTokens.contains(token)) return 'abusive language';
    }
    return null;
  }

  static String _normalise(String text) {
    String value = text.toLowerCase();
    value = value.replaceAllMapped(
      RegExp(r'[@0!1$3]'),
      (Match match) => switch (match.group(0)) {
        '@' => 'a',
        '0' => 'o',
        '!' => 'i',
        '1' => 'i',
        r'$' => 's',
        '3' => 'e',
        _ => match.group(0)!,
      },
    );
    value = value.replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ');
    return value.trim();
  }

  static Iterable<String> _tokens(String normalised) => normalised
      .split(RegExp(r'\s+'))
      .where((String token) => token.isNotEmpty);
}
