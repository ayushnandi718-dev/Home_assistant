import 'package:aura_hub/features/dashboard/domain/activity_event.dart';

/// Connection and refresh state published by the dashboard sync controller.
///
/// Kept separate from [DashboardSnapshot] so the app bar can show connection
/// health without subscribing to (and therefore keeping alive) the polling
/// stream while the dashboard is not open.
class DashboardConnectionStatus {
  const DashboardConnectionStatus({
    this.active = false,
    this.localApiOnline = false,
    this.stale = false,
    this.refreshing = false,
    this.lastSuccess,
    this.error,
    this.activity = const <ActivityEvent>[],
  });

  /// True only while the dashboard owns the polling controller.
  final bool active;
  final bool localApiOnline;
  final bool stale;
  final bool refreshing;
  final DateTime? lastSuccess;
  final Object? error;
  final List<ActivityEvent> activity;

  String get label {
    if (!active) return 'Host API idle';
    if (stale) return 'Reconnecting';
    if (refreshing && lastSuccess != null) return 'Syncing';
    return localApiOnline ? 'Host API online' : 'Host API offline';
  }
}
