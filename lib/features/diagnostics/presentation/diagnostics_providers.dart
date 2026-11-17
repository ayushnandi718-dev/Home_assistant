import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/domain/sampler_health.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Ring buffer of recent API requests for the Diagnostics page.
/// Bounded so a long-running app cannot grow memory without limit.
class DiagnosticsNotifier extends StateNotifier<List<ApiRequestRecord>> {
  DiagnosticsNotifier() : super(const <ApiRequestRecord>[]);

  static const int maxRecords = 100;

  void record(ApiRequestRecord entry) {
    state = <ApiRequestRecord>[entry, ...state].take(maxRecords).toList();
  }

  void clear() => state = const <ApiRequestRecord>[];
}

final StateNotifierProvider<DiagnosticsNotifier, List<ApiRequestRecord>>
    diagnosticsProvider =
    StateNotifierProvider<DiagnosticsNotifier, List<ApiRequestRecord>>(
  (Ref ref) => DiagnosticsNotifier(),
);

/// Latest explicit /api/health result, produced from Settings or a client.
/// Both reachable and failed checks are stored so the UI can be honest.
class ApiHealthNotifier extends StateNotifier<ApiHealth?> {
  ApiHealthNotifier() : super(null);

  void record(ApiHealth health) => state = health;
  void clear() => state = null;
}

final StateNotifierProvider<ApiHealthNotifier, ApiHealth?> apiHealthProvider =
    StateNotifierProvider<ApiHealthNotifier, ApiHealth?>(
  (Ref ref) => ApiHealthNotifier(),
);

/// Bounded history of explicit health checks, separate from telemetry requests.
class ApiHealthHistoryNotifier extends StateNotifier<List<ApiHealth>> {
  ApiHealthHistoryNotifier() : super(const <ApiHealth>[]);

  static const int maxRecords = 20;

  void record(ApiHealth health) {
    state = <ApiHealth>[health, ...state].take(maxRecords).toList();
  }

  void clear() => state = const <ApiHealth>[];
}

final StateNotifierProvider<ApiHealthHistoryNotifier, List<ApiHealth>>
    apiHealthHistoryProvider =
    StateNotifierProvider<ApiHealthHistoryNotifier, List<ApiHealth>>(
  (Ref ref) => ApiHealthHistoryNotifier(),
);

/// Separate bounded history of sampler status observations. Sampler failures
/// must never be confused with HTTP request failures.
class SamplerDiagnosticsNotifier extends StateNotifier<List<SamplerHealth>> {
  SamplerDiagnosticsNotifier() : super(const <SamplerHealth>[]);

  static const int maxRecords = 50;

  void observe(SamplerHealth health) {
    state = <SamplerHealth>[health, ...state].take(maxRecords).toList();
  }

  void clear() => state = const <SamplerHealth>[];
}

final StateNotifierProvider<SamplerDiagnosticsNotifier, List<SamplerHealth>>
    samplerDiagnosticsProvider =
    StateNotifierProvider<SamplerDiagnosticsNotifier, List<SamplerHealth>>(
  (Ref ref) => SamplerDiagnosticsNotifier(),
);

/// Cross-category diagnostic events. Used by device lifecycle transitions as
/// well as health checks, so no category can hide behind another one.
typedef DiagnosticRecorder = void Function(
  DiagnosticCategory category,
  String message, {
  bool succeeded,
  String? error,
  Duration? duration,
});

class DiagnosticEventsNotifier extends StateNotifier<List<DiagnosticEvent>> {
  DiagnosticEventsNotifier() : super(const <DiagnosticEvent>[]);

  static const int maxRecords = 100;

  void record(
    DiagnosticCategory category,
    String message, {
    bool succeeded = true,
    String? error,
    Duration? duration,
  }) {
    state = <DiagnosticEvent>[
      DiagnosticEvent(
        category: category,
        message: message,
        timestamp: DateTime.now(),
        succeeded: succeeded,
        error: error,
        duration: duration,
      ),
      ...state,
    ].take(maxRecords).toList();
  }

  void clear() => state = const <DiagnosticEvent>[];
}

final StateNotifierProvider<DiagnosticEventsNotifier, List<DiagnosticEvent>>
    diagnosticEventsProvider =
    StateNotifierProvider<DiagnosticEventsNotifier, List<DiagnosticEvent>>(
  (Ref ref) => DiagnosticEventsNotifier(),
);
