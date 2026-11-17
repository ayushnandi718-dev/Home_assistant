import 'package:aura_hub/core/network/aura_api_client.dart';
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
