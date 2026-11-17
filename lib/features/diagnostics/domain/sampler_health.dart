import 'package:aura_hub/core/utilities/redaction.dart';

/// Health of the Python background sampler, reported by the local API.
///
/// This is deliberately separate from HTTP request records: a request can
/// succeed while the sampler is still initialising or has just failed.
enum SamplerReadiness { initializing, ready, degraded }

class SamplerHealth {
  SamplerHealth({
    required this.ready,
    required this.healthy,
    required this.consecutiveFailures,
    this.lastSuccessAt,
    this.lastFailureAt,
    this.lastError,
    DateTime? observedAt,
  }) : observedAt = observedAt ?? DateTime.now();

  factory SamplerHealth.fromJson(Map<String, dynamic> json) {
    return SamplerHealth(
      ready: json['ready'] == true,
      healthy: json['healthy'] == true,
      consecutiveFailures: (json['consecutiveFailures'] as num?)?.toInt() ?? 0,
      lastSuccessAt: _date(json['lastSuccessAt']),
      lastFailureAt: _date(json['lastFailureAt']),
      lastError: json['lastError']?.toString(),
    );
  }

  static DateTime? _date(Object? value) =>
      value == null ? null : DateTime.tryParse(value.toString());

  final bool ready;
  final bool healthy;
  final int consecutiveFailures;
  final DateTime? lastSuccessAt;
  final DateTime? lastFailureAt;

  /// Exception type only. The Python API never sends exception messages.
  final String? lastError;

  /// When the Flutter app observed this sampler status.
  final DateTime observedAt;

  SamplerReadiness get status {
    if (!ready) return SamplerReadiness.initializing;
    return healthy ? SamplerReadiness.ready : SamplerReadiness.degraded;
  }

  bool get hasFailure => lastError != null || consecutiveFailures > 0;

  String get label {
    switch (status) {
      case SamplerReadiness.initializing:
        return 'Initializing';
      case SamplerReadiness.ready:
        return 'Healthy';
      case SamplerReadiness.degraded:
        return 'Degraded';
    }
  }

  /// Safe for export: no payloads, no credentials, no raw paths or URLs.
  Map<String, dynamic> toJson() => <String, dynamic>{
        'observedAt': observedAt.toIso8601String(),
        'status': label,
        'ready': ready,
        'healthy': healthy,
        'consecutiveFailures': consecutiveFailures,
        'lastSuccessAt': lastSuccessAt?.toIso8601String(),
        'lastFailureAt': lastFailureAt?.toIso8601String(),
        if (lastError != null) 'lastError': Redaction.sanitise(lastError!),
      };
}
