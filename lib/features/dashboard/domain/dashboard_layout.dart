/// Widgets in the dashboard body whose order, visibility and size are
/// user-owned.
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

/// Column span in the dashboard's three-column bento grid.
///
/// Narrow windows collapse the grid to two or one column; spans are clamped at
/// render time so a saved layout can never overflow the available width.
enum DashboardWidgetSize { compact, medium, full }

extension DashboardWidgetSizeX on DashboardWidgetSize {
  int get span {
    switch (this) {
      case DashboardWidgetSize.compact:
        return 1;
      case DashboardWidgetSize.medium:
        return 2;
      case DashboardWidgetSize.full:
        return 3;
    }
  }

  String get label {
    switch (this) {
      case DashboardWidgetSize.compact:
        return 'Compact';
      case DashboardWidgetSize.medium:
        return 'Medium';
      case DashboardWidgetSize.full:
        return 'Full width';
    }
  }
}

DashboardWidgetId? _idFromName(Object? name) {
  for (final DashboardWidgetId value in DashboardWidgetId.values) {
    if (value.name == name) return value;
  }
  return null;
}

DashboardWidgetSize? _sizeFromName(Object? name) {
  for (final DashboardWidgetSize value in DashboardWidgetSize.values) {
    if (value.name == name) return value;
  }
  return null;
}

DashboardWidgetSize _defaultSizeFor(DashboardWidgetId id) =>
    DashboardLayout.defaults.widgets
        .firstWhere((DashboardWidgetConfig item) => item.id == id)
        .size;

class DashboardWidgetConfig {
  const DashboardWidgetConfig({
    required this.id,
    required this.visible,
    this.size = DashboardWidgetSize.full,
  });

  final DashboardWidgetId id;
  final bool visible;
  final DashboardWidgetSize size;

  DashboardWidgetConfig copyWith({
    bool? visible,
    DashboardWidgetSize? size,
  }) =>
      DashboardWidgetConfig(
        id: id,
        visible: visible ?? this.visible,
        size: size ?? this.size,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id.name,
        'visible': visible,
        'size': size.name,
      };

  factory DashboardWidgetConfig.fromJson(Map<String, dynamic> json) {
    final DashboardWidgetId id =
        _idFromName(json['id']) ?? DashboardWidgetId.overview;
    return DashboardWidgetConfig(
      id: id,
      visible: json['visible'] != false,
      size: _sizeFromName(json['size']) ?? _defaultSizeFor(id),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DashboardWidgetConfig &&
          other.id == id &&
          other.visible == visible &&
          other.size == size;

  @override
  int get hashCode => Object.hash(id, visible, size);
}

/// Immutable, validated dashboard layout.
class DashboardLayout {
  const DashboardLayout(this.widgets);

  /// Balanced default bento: overview and notifications own a full row, while
  /// the remaining widgets pair naturally in a three-column grid.
  static const DashboardLayout defaults =
      DashboardLayout(<DashboardWidgetConfig>[
    DashboardWidgetConfig(
      id: DashboardWidgetId.overview,
      visible: true,
      size: DashboardWidgetSize.full,
    ),
    DashboardWidgetConfig(
      id: DashboardWidgetId.history,
      visible: true,
      size: DashboardWidgetSize.medium,
    ),
    DashboardWidgetConfig(
      id: DashboardWidgetId.spotlight,
      visible: true,
      size: DashboardWidgetSize.compact,
    ),
    DashboardWidgetConfig(
      id: DashboardWidgetId.quickActions,
      visible: true,
      size: DashboardWidgetSize.compact,
    ),
    DashboardWidgetConfig(
      id: DashboardWidgetId.activity,
      visible: true,
      size: DashboardWidgetSize.medium,
    ),
    DashboardWidgetConfig(
      id: DashboardWidgetId.notifications,
      visible: true,
      size: DashboardWidgetSize.full,
    ),
  ]);

  final List<DashboardWidgetConfig> widgets;

  List<DashboardWidgetConfig> get visibleConfigs => widgets
      .where((DashboardWidgetConfig item) => item.visible)
      .toList(growable: false);

  bool isVisible(DashboardWidgetId id) => widgets.any(
        (DashboardWidgetConfig item) => item.id == id && item.visible,
      );

  DashboardWidgetSize sizeOf(DashboardWidgetId id) => widgets
      .firstWhere(
        (DashboardWidgetConfig item) => item.id == id,
        orElse: () => const DashboardWidgetConfig(
          id: DashboardWidgetId.overview,
          visible: true,
        ),
      )
      .size;

  DashboardLayout toggle(DashboardWidgetId id) => DashboardLayout(
        widgets
            .map(
              (DashboardWidgetConfig item) =>
                  item.id == id ? item.copyWith(visible: !item.visible) : item,
            )
            .toList(growable: false),
      );

  DashboardLayout setSize(DashboardWidgetId id, DashboardWidgetSize size) =>
      DashboardLayout(
        widgets
            .map(
              (DashboardWidgetConfig item) =>
                  item.id == id ? item.copyWith(size: size) : item,
            )
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
        'version': 2,
        'widgets': widgets
            .map((DashboardWidgetConfig item) => item.toJson())
            .toList(growable: false),
      };

  /// Repairs a hand-edited file: unknown ids are dropped, missing ids are
  /// appended in their default order, and duplicates are ignored. Version 1
  /// files (order/visibility only) receive the matching default sizes.
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
      restored.add(DashboardWidgetConfig(
        id: id,
        visible: item['visible'] != false,
        size: _sizeFromName(item['size']) ?? _defaultSizeFor(id),
      ));
    }
    for (final DashboardWidgetConfig item in defaults.widgets) {
      if (seen.add(item.id)) restored.add(item);
    }
    return DashboardLayout(restored);
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
