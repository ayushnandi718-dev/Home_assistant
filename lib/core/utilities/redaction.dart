/// Removes values that should never appear in an exported diagnostic file.
///
/// API endpoints, exception text and sampler errors are useful on screen, but
/// they can contain URLs or local paths. Exports keep the diagnostic shape
/// while replacing those values with placeholders.
abstract final class Redaction {
  static String sanitise(String value) {
    String result = value.replaceAllMapped(
      RegExp(r'https?://[^\s,;"]+'),
      (_) => '<url>',
    );
    result = result.replaceAllMapped(
      RegExp(r'[A-Za-z]:\\[^\s,;"]+'),
      (_) => '<path>',
    );
    result = result.replaceAllMapped(
      RegExp(r'\\\\[^\s,;"]+'),
      (_) => '<path>',
    );
    return result.replaceAllMapped(
      RegExp(r'/(?:home|Users)/[^\s,;"]+'),
      (_) => '<path>',
    );
  }
}
