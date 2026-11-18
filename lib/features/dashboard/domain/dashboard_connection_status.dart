/// Connection and refresh state published by the dashboard sync controller.
///
/// Kept separate from [DashboardSnapshot] so the app bar can show connection
/// health without subscribing to (and therefore keeping alive) the polling
/// stream while the dashboard is not open.
///
/// Only fields that affect UI are stored here. In particular, the activity feed
/// stays on the snapshot: copying it into every status update would notify the
/// whole shell on each poll even though nothing displays it.
class DashboardConnectionStatus {
  const DashboardConnectionStatus({
    this.active = false,
    this.localApiOnline = false,
    this.stale = false,
    this.refreshing = false,
    this.consecutiveFailures = 0,
    this.lastSuccess,
    this.error,
  });

  /// True only while the dashboard owns the polling controller.
  final bool active;
  final bool localApiOnline;
  final bool stale;
  final bool refreshing;

  /// Number of consecutive failed polls since the last success.
  final int consecutiveFailures;
  final DateTime? lastSuccess;
  final Object? error;

  String get label {
    if (!active) return 'Host API idle';
    if (stale) return 'Reconnecting';
    if (refreshing && lastSuccess != null) return 'Syncing';
    return localApiOnline ? 'Host API online' : 'Host API offline';
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardConnectionStatus &&
          other.active == active &&
          other.localApiOnline == localApiOnline &&
          other.stale == stale &&
          other.refreshing == refreshing &&
          other.consecutiveFailures == consecutiveFailures &&
          other.lastSuccess == lastSuccess &&
          other.error == error;

  @override
  int get hashCode => Object.hash(
        active,
        localApiOnline,
        stale,
        refreshing,
        consecutiveFailures,
        lastSuccess,
        error,
      );
}
