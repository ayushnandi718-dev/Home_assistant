/// Widgets in the dashboard body whose order and visibility are user-owned.
///
/// Status bars (live-data notice and source health) are deliberately excluded:
/// they must always be visible so data provenance is never hidden.
enum DashboardWidgetId {
  overview,
  history,
  spotlight,
  quickActions,
  activity,
  notifications,
}

extension DashboardWidgetIdX on DashboardWidgetId {
  String get label {
    switch (this) {
      case DashboardWidgetId.overview:
        return 'System overview';
      case DashboardWidgetId.history:
        return 'Telemetry history';
      case DashboardWidgetId.spotlight:
        return 'AURA device';
      case DashboardWidgetId.quickActions:
        return 'Quick actions';
      case DashboardWidgetId.activity:
        return 'Recent activity';
      case DashboardWidgetId.notifications:
        return 'Notification summary';
    }
  }

  String get description {
    switch (this) {
      case DashboardWidgetId.overview:
        return 'Live CPU, memory, disk and network readings.';
      case DashboardWidgetId.history:
        return 'Bounded session chart of successful samples.';
      case DashboardWidgetId.spotlight:
        return 'Honest AURA Core connection state.';
      case DashboardWidgetId.quickActions:
        return 'Navigation shortcuts to AURA modules.';
      case DashboardWidgetId.activity:
        return 'Recent real Windows host events.';
      case DashboardWidgetId.notifications:
        return 'Unread counter and latest service notifications.';
    }
  }
}

class DashboardWidgetConfig {
  const DashboardWidgetConfig({required this.id, required this.visible});

  final DashboardWidgetId id;
  final bool visible;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id.name,
        'visible': visible,
      };

  factory DashboardWidgetConfig.fromJson(Map<String, dynamic> json) {
    final DashboardWidgetId id = DashboardWidgetId.values.firstWhere(
      (DashboardWidgetId item) => item.name == json['id'],
      orElse: () => DashboardWidgetId.overview,
    );
    return DashboardWidgetConfig(id: id, visible: json['visible'] != false);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardWidgetConfig &&
          other.id == id &&
          other.visible == visible;

  @override
  int get hashCode => Object.hash(id, visible);
}

/// Immutable, validated dashboard layout.
class DashboardLayout {
  const DashboardLayout(this.widgets);

  static const DashboardLayout defaults =
      DashboardLayout(<DashboardWidgetConfig>[
    DashboardWidgetConfig(id: DashboardWidgetId.overview, visible: true),
    DashboardWidgetConfig(id: DashboardWidgetId.history, visible: true),
    DashboardWidgetConfig(id: DashboardWidgetId.spotlight, visible: true),
    DashboardWidgetConfig(id: DashboardWidgetId.quickActions, visible: true),
    DashboardWidgetConfig(id: DashboardWidgetId.activity, visible: true),
    DashboardWidgetConfig(id: DashboardWidgetId.notifications, visible: true),
  ]);

  final List<DashboardWidgetConfig> widgets;

  bool isVisible(DashboardWidgetId id) => widgets.any(
        (DashboardWidgetConfig item) => item.id == id && item.visible,
      );

  DashboardLayout toggle(DashboardWidgetId id) => DashboardLayout(
        widgets
            .map((DashboardWidgetConfig item) => item.id == id
                ? DashboardWidgetConfig(id: id, visible: !item.visible)
                : item)
            .toList(growable: false),
      );

  DashboardLayout reorder(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= widgets.length || newIndex < 0) {
      return this;
    }
    int target = newIndex > oldIndex ? newIndex - 1 : newIndex;
    if (target >= widgets.length) target = widgets.length - 1;
    final List<DashboardWidgetConfig> next =
        List<DashboardWidgetConfig>.from(widgets);
    final DashboardWidgetConfig moved = next.removeAt(oldIndex);
    next.insert(target, moved);
    return DashboardLayout(next);
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'widgets': widgets
            .map((DashboardWidgetConfig item) => item.toJson())
            .toList(growable: false),
      };

  /// Repairs a hand-edited file: unknown ids are dropped, missing ids are
  /// appended in their default order, and duplicates are ignored.
  factory DashboardLayout.fromJson(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return defaults;
    final Object? rawWidgets = decoded['widgets'];
    if (rawWidgets is! List<dynamic>) return defaults;

    final List<DashboardWidgetConfig> restored = <DashboardWidgetConfig>[];
    final Set<DashboardWidgetId> seen = <DashboardWidgetId>{};
    for (final Object? item in rawWidgets) {
      if (item is! Map<String, dynamic>) continue;
      final DashboardWidgetId? id = _idFromName(item['id']);
      if (id == null || !seen.add(id)) continue;
      restored.add(
        DashboardWidgetConfig(id: id, visible: item['visible'] != false),
      );
    }
    for (final DashboardWidgetConfig item in defaults.widgets) {
      if (seen.add(item.id)) restored.add(item);
    }
    return DashboardLayout(restored);
  }

  static DashboardWidgetId? _idFromName(Object? name) {
    for (final DashboardWidgetId value in DashboardWidgetId.values) {
      if (value.name == name) return value;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardLayout && _sameWidgets(other.widgets, widgets);

  @override
  int get hashCode => Object.hashAll(widgets);

  static bool _sameWidgets(
    List<DashboardWidgetConfig> left,
    List<DashboardWidgetConfig> right,
  ) {
    if (left.length != right.length) return false;
    for (int index = 0; index < left.length; index++) {
      if (left[index] != right[index]) return false;
    }
    return true;
  }
}
