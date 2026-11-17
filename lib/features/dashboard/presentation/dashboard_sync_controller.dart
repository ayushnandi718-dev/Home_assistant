import 'dart:async';

import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';

typedef DashboardSnapshotFetcher = Future<DashboardSnapshot> Function();
typedef DashboardStatusListener = void Function(
    DashboardConnectionStatus status);

/// Owns telemetry polling for the dashboard.
///
/// The timer and stream live here rather than in a widget, so navigation and
/// rebuilds never create duplicate subscriptions. Requests are serialised: a
/// new poll cannot start while the previous HTTP call is still in flight.
class DashboardSyncController {
  DashboardSyncController({
    required DashboardSnapshotFetcher fetch,
    required Duration interval,
    this.onStatus,
  })  : _fetch = fetch,
        _interval = interval;

  final DashboardSnapshotFetcher _fetch;
  final Duration _interval;
  final DashboardStatusListener? onStatus;
  final StreamController<DashboardSnapshot> _controller =
      StreamController<DashboardSnapshot>.broadcast();

  Timer? _timer;
  bool _fetching = false;
  bool _disposed = false;
  bool _active = false;
  DashboardSnapshot? _lastSuccessful;
  Object? _error;
  int _consecutiveFailures = 0;

  Stream<DashboardSnapshot> get stream => _controller.stream;

  /// Fetches immediately, then every [interval] while this controller lives.
  void start() {
    if (_disposed || _timer != null) return;
    _active = true;
    _publish();
    unawaited(refresh());
    _timer = Timer.periodic(_interval, (Timer _) {
      unawaited(refresh());
    });
  }

  /// Manual refresh. Ignored while a fetch is already running.
  Future<void> refresh() async {
    if (_fetching || _disposed) return;
    _fetching = true;
    _publish();
    try {
      final DashboardSnapshot next = await _fetch();
      if (_disposed) return;
      _lastSuccessful = next;
      _error = null;
      _consecutiveFailures = 0;
      _emit(next);
    } catch (error, stackTrace) {
      if (_disposed) return;
      _error = error;
      _consecutiveFailures++;
      final DashboardSnapshot? last = _lastSuccessful;
      if (last == null) {
        // Nothing to fall back to yet: surface the first-load failure.
        if (!_controller.isClosed) {
          _controller.addError(error, stackTrace);
        }
      } else {
        // Keep the last good readings and flag them as stale. The next poll
        // retries automatically.
        _emit(last.copyWith(localApiOnline: false, stale: true));
      }
    } finally {
      _fetching = false;
      _publish();
    }
  }

  void _emit(DashboardSnapshot snapshot) {
    if (!_disposed && !_controller.isClosed) {
      _controller.add(snapshot);
    }
  }

  void _publish() {
    onStatus?.call(
      DashboardConnectionStatus(
        active: _active,
        localApiOnline: _lastSuccessful != null && _error == null,
        stale: _error != null && _lastSuccessful != null,
        refreshing: _fetching,
        consecutiveFailures: _consecutiveFailures,
        lastSuccess: _lastSuccessful?.generatedAt,
        error: _error,
        activity: _lastSuccessful?.activity ?? const <ActivityEvent>[],
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _active = false;
    _disposed = true;
    _timer?.cancel();
    _controller.close();
    _publish();
  }
}
