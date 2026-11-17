import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/utilities/redaction.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Severity of a structured AURA log entry.
enum AuraLogLevel { debug, info, warning, error }

/// One structured log record.
///
/// Message and context values are redacted at construction, so no URL, local
/// path or token can reach the in-memory log or an exported diagnostic file.
class AuraLogEntry {
  const AuraLogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    this.context = const <String, String>{},
  });

  final DateTime timestamp;
  final AuraLogLevel level;
  final String category;
  final String message;
  final Map<String, String> context;

  String get levelLabel => level.name.toUpperCase();

  Map<String, dynamic> toJson() => <String, dynamic>{
        'timestamp': timestamp.toIso8601String(),
        'level': levelLabel,
        'category': Redaction.sanitise(category),
        'message': Redaction.sanitise(message),
        'context': context.map(
          (String key, String value) =>
              MapEntry<String, String>(key, Redaction.sanitise(value)),
        ),
      };
}

/// Application-wide structured logger.
///
/// Keeps a bounded in-memory buffer. It is deliberately not written to disk:
/// diagnostics export is the only way log records leave the process.
class AuraLogger extends StateNotifier<List<AuraLogEntry>> {
  AuraLogger() : super(const <AuraLogEntry>[]);

  void log(
    AuraLogLevel level,
    String category,
    String message, {
    Map<String, String> context = const <String, String>{},
  }) {
    final AuraLogEntry entry = AuraLogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: Redaction.sanitise(message),
      context: context.map(
        (String key, String value) =>
            MapEntry<String, String>(key, Redaction.sanitise(value)),
      ),
    );
    state = <AuraLogEntry>[entry, ...state]
        .take(AuraRuntimeConfig.maxLogEntries)
        .toList();
  }

  void debug(String category, String message,
          {Map<String, String> context = const <String, String>{}}) =>
      log(AuraLogLevel.debug, category, message, context: context);

  void info(String category, String message,
          {Map<String, String> context = const <String, String>{}}) =>
      log(AuraLogLevel.info, category, message, context: context);

  void warning(String category, String message,
          {Map<String, String> context = const <String, String>{}}) =>
      log(AuraLogLevel.warning, category, message, context: context);

  void error(String category, String message,
          {Map<String, String> context = const <String, String>{}}) =>
      log(AuraLogLevel.error, category, message, context: context);

  void clear() => state = const <AuraLogEntry>[];
}

final StateNotifierProvider<AuraLogger, List<AuraLogEntry>> auraLoggerProvider =
    StateNotifierProvider<AuraLogger, List<AuraLogEntry>>(
  (Ref ref) => AuraLogger(),
);
