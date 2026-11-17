enum ActivityCategory { system, device, security, integration }

enum ActivitySeverity { info, warning, error }

class ActivityEvent {
  const ActivityEvent({
    required this.id,
    required this.title,
    required this.detail,
    required this.category,
    required this.severity,
    required this.timestamp,
    required this.isDemo,
  });

  final String id;
  final String title;
  final String detail;
  final ActivityCategory category;
  final ActivitySeverity severity;
  final DateTime timestamp;
  final bool isDemo;
}
