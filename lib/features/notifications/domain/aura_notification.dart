/// Importance of a notification shown in the central notification centre.
enum NotificationSeverity { info, success, warning, error }

/// Where a notification came from. Used for filtering and clear boundaries.
enum NotificationSource {
  system,
  api,
  sampler,
  device,
  profile,
  integration,
  ai
}

/// A real event produced by AURA Hub. No sample notifications are created.
class AuraNotification {
  const AuraNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.severity,
    required this.source,
    required this.timestamp,
    this.isRead = false,
  });

  final String id;
  final String title;
  final String body;
  final NotificationSeverity severity;
  final NotificationSource source;
  final DateTime timestamp;
  final bool isRead;

  AuraNotification copyWith({bool? isRead}) => AuraNotification(
        id: id,
        title: title,
        body: body,
        severity: severity,
        source: source,
        timestamp: timestamp,
        isRead: isRead ?? this.isRead,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'title': title,
        'body': body,
        'severity': severity.name,
        'source': source.name,
        'timestamp': timestamp.toIso8601String(),
        'isRead': isRead,
      };

  factory AuraNotification.fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Notification id is missing.');
    }
    return AuraNotification(
      id: id,
      title: (json['title'] as String?) ?? 'Notification',
      body: (json['body'] as String?) ?? '',
      severity: _severity(json['severity'] as String?),
      source: _source(json['source'] as String?),
      timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      isRead: json['isRead'] == true,
    );
  }

  static NotificationSeverity _severity(String? value) =>
      NotificationSeverity.values.firstWhere(
        (NotificationSeverity item) => item.name == value,
        orElse: () => NotificationSeverity.info,
      );

  static NotificationSource _source(String? value) =>
      NotificationSource.values.firstWhere(
        (NotificationSource item) => item.name == value,
        orElse: () => NotificationSource.system,
      );
}
