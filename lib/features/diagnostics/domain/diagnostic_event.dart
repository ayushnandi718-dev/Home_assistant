import 'package:aura_hub/core/utilities/redaction.dart';

/// Categories kept separate so diagnostics never merge unrelated failures.
enum DiagnosticCategory {
  apiHealth,
  telemetry,
  sampler,
  deviceDiscovery,
  devicePairing,
  deviceConnection,
}

extension DiagnosticCategoryLabel on DiagnosticCategory {
  String get label => switch (this) {
        DiagnosticCategory.apiHealth => 'API health',
        DiagnosticCategory.telemetry => 'Telemetry request',
        DiagnosticCategory.sampler => 'Sampler',
        DiagnosticCategory.deviceDiscovery => 'Device discovery',
        DiagnosticCategory.devicePairing => 'Device pairing',
        DiagnosticCategory.deviceConnection => 'Device connection',
      };
}

/// A timestamped, redaction-safe diagnostic observation.
class DiagnosticEvent {
  const DiagnosticEvent({
    required this.category,
    required this.message,
    required this.timestamp,
    this.duration,
    this.error,
    this.succeeded = true,
  });

  final DiagnosticCategory category;
  final String message;
  final DateTime timestamp;
  final Duration? duration;
  final String? error;
  final bool succeeded;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'category': category.name,
        'categoryLabel': category.label,
        'timestamp': timestamp.toIso8601String(),
        if (duration != null) 'durationMs': duration!.inMilliseconds,
        'succeeded': succeeded,
        'message': Redaction.sanitise(message),
        if (error != null) 'error': Redaction.sanitise(error!),
      };
}
