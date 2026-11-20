import 'package:aura_hub/core/services/clock_service.dart';

/// Adds fresh runtime time information to relevant AI requests.
///
/// This is contextual system information, not a tool call and not a change to
/// the base assistant policy. It is read at assembly time for each matching
/// request, so a cached or memorised answer can never become authoritative.
abstract final class AiRuntimeTimeContext {
  static final RegExp _whatTime = RegExp(
      r"\bwhat(?:'s|\s+is)\s+(?:the\s+)?(?:current\s+|local\s+)?time\b",
      caseSensitive: false);
  static final RegExp _whatTimeIsIt =
      RegExp(r'\bwhat\s+time\s+is\s+it\b', caseSensitive: false);
  static final RegExp _currentOrLocalTime =
      RegExp(r'\b(?:current|local)\s+time\b', caseSensitive: false);
  static final RegExp _tellMeTheTime =
      RegExp(r'\btell\s+me\s+the\s+time\b', caseSensitive: false);
  static final RegExp _timeInPlace =
      RegExp(r'\b(?:local\s+)?time\s+in\s+\S', caseSensitive: false);
  static final RegExp _timeWillItBe = RegExp(
      r'\bwhat\s+time\s+(?:will|would)\s+it\s+be\b',
      caseSensitive: false);
  static final RegExp _timeNow =
      RegExp(r'\btime\s+(?:right\s+)?now\b', caseSensitive: false);
  static final RegExp _timeOfDayInPlace = RegExp(
      r'\b(?:morning|afternoon|evening|night|noon|midnight)\s+in\s+\S',
      caseSensitive: false);
  static final RegExp _dateQuestion = RegExp(
      r"\b(?:what(?:'s|\s+is)\s+(?:the\s+)?(?:current\s+|today'?s?\s+|tomorrow'?s?\s+|yesterday'?s?\s+)?date|today'?s?\s+date|tomorrow'?s?\s+date|yesterday'?s?\s+date|current\s+date|date\s+(?:today|tomorrow|yesterday))\b",
      caseSensitive: false);
  static final RegExp _dayQuestion = RegExp(
      r'\b(?:what\s+day\s+is\s+it\b|what\s+day\s+(?:is|was|will\s+be)\s+(?:it\s+)?(?:today|tomorrow|yesterday)\b|day\s+of\s+(?:the\s+)?week\b|what\s+weekday\b)',
      caseSensitive: false);
  static final RegExp _utcOffset = RegExp(
      r'\b(?:current\s+)?(?:utc|gmt)\s+offset\b|\b(?:utc|gmt)(?:\s*[+-]\s*\d{1,2}(?::?\d{2})?)?\b.*\b(?:offset|time)\b|\boffset\b.*\b(?:utc|gmt)\b',
      caseSensitive: false);
  static final RegExp _timeZone = RegExp(
      r'\btime\s*zone\b|\btimezone\b|\bcurrent\s+(?:utc|gmt)\b',
      caseSensitive: false);
  static final RegExp _durationUntil = RegExp(
      r'\bhow\s+(?:many|much|long)\s+(?:hours?|minutes?|seconds?|time)\s+(?:until|till|before|from\s+now\s+until|from\s+now\s+till)\b|\b(?:hours?|minutes?|seconds?)\s+(?:until|till)\s+(?:midnight|noon|\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?)\b',
      caseSensitive: false);
  static final RegExp _whenItIsClockTime = RegExp(
      r"\bwhen\s+it(?:'s|\s+is)\s+\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)?\b",
      caseSensitive: false);
  static final RegExp _clockTimeToken = RegExp(
      r'\b\d{1,2}(?::\d{2})?\s*(?:a\.?m\.?|p\.?m\.?)\b',
      caseSensitive: false);
  static final RegExp _timeZoneToken = RegExp(
      r'\b(?:ist|utc|gmt|cet|eet|est|edt|cst|cdt|mst|mdt|pst|pdt|bst|jst|aest|aedt|nzst|nzdt)\b',
      caseSensitive: false);
  static final RegExp _convertIntent =
      RegExp(r'\bconvert\b', caseSensitive: false);
  static final RegExp _timeWord =
      RegExp(r'\b(?:time|clock)\b', caseSensitive: false);

  /// Whether the prompt is asking for current time, date, timezone, or a
  /// time calculation/conversion.
  ///
  /// Phrase/intent-based so ordinary prompts containing words like "am",
  /// "now", or "current" do not pay for clock context.
  static bool isTimeRelated(String prompt) {
    final String text = prompt.trim();
    if (text.isEmpty) return false;

    if (_whatTime.hasMatch(text) ||
        _whatTimeIsIt.hasMatch(text) ||
        _currentOrLocalTime.hasMatch(text) ||
        _tellMeTheTime.hasMatch(text) ||
        _timeInPlace.hasMatch(text) ||
        _timeWillItBe.hasMatch(text) ||
        _timeNow.hasMatch(text) ||
        _timeOfDayInPlace.hasMatch(text) ||
        _dateQuestion.hasMatch(text) ||
        _dayQuestion.hasMatch(text) ||
        _durationUntil.hasMatch(text) ||
        _whenItIsClockTime.hasMatch(text)) {
      return true;
    }

    // "Current UTC offset" / timezone questions are time-related, but avoid
    // broad bare-token matches for unrelated uses of "current" or "time".
    if (_utcOffset.hasMatch(text)) return true;
    if (RegExp(r'\b(?:what|which|current|my|local)\b', caseSensitive: false)
            .hasMatch(text) &&
        _timeZone.hasMatch(text)) {
      return true;
    }

    // Conversions like "Convert 8 PM IST to New York time".
    if (_convertIntent.hasMatch(text)) {
      if (_clockTimeToken.hasMatch(text) ||
          _timeZoneToken.hasMatch(text) ||
          _timeWord.hasMatch(text)) {
        return true;
      }
    }

    return false;
  }

  /// Returns a fresh, secret-free system instruction, or null when the prompt
  /// does not ask about time.
  static String? instructionFor(
    String prompt, {
    AuraClock? clock,
    AuraCityTimeZoneResolver? resolver,
  }) {
    if (!isTimeRelated(prompt)) return null;

    final AuraClock activeClock = clock ?? SystemAuraClock.instance;
    final AuraCityTimeZoneResolver activeResolver =
        resolver ?? const CuratedCityTimeZoneResolver();
    final List<String> mentioned = activeResolver.mentionedIn(prompt);

    return readAuraTime(
      activeClock,
      locationHint: mentioned.isEmpty ? null : mentioned.first,
      resolver: activeResolver,
    ).describe(activeClock);
  }
}
