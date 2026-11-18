/// Deterministic local check that rejects credential-like memory content.
///
/// It is intentionally conservative and never returns the rejected text. This
/// is a guardrail, not a classifier: ordinary preferences and project notes are
/// unaffected, while obvious passwords, keys, PINs, OTPs and card details are
/// refused before they reach persistent storage.
abstract final class MemorySafety {
  static const String rejectedMessage =
      'AURA cannot store passwords, API keys, PINs, OTPs, authentication codes '
      'or financial details.';

  static final List<RegExp> _patterns = <RegExp>[
    RegExp(r'\b(?:password|passcode|pwd)\b', caseSensitive: false),
    RegExp(
      r'\b(?:api[\s_-]*key|access[\s_-]*token|refresh[\s_-]*token|secret|'
      r'bearer|authorization)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:pin|otp|one[\s-]?time(?:\s+(?:code|password))?)\b',
      caseSensitive: false,
    ),
    RegExp(
      r'\b(?:cvv|cvc|card[\s_-]*number|credit[\s_-]*card|debit[\s_-]*card|'
      r'iban|swift)\b',
      caseSensitive: false,
    ),
    RegExp(r'\b\d{8,}\b'),
  ];

  static bool isSensitive(String text) {
    final String value = text.trim();
    if (value.isEmpty) return false;
    for (final RegExp pattern in _patterns) {
      if (pattern.hasMatch(value)) return true;
    }
    return false;
  }

  static String? rejectionFor(String text) =>
      isSensitive(text) ? rejectedMessage : null;
}
