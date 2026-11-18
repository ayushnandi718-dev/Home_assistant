/// Per-profile memory controls. Retrieval is opt-in; suggestions stay pending
/// until the user approves them and can be disabled independently.
class MemorySettings {
  const MemorySettings({
    this.retrievalEnabled = false,
    this.suggestionsEnabled = true,
  });

  static const MemorySettings defaults = MemorySettings();
  static const int schemaVersion = 1;

  final bool retrievalEnabled;
  final bool suggestionsEnabled;

  MemorySettings copyWith({
    bool? retrievalEnabled,
    bool? suggestionsEnabled,
  }) {
    return MemorySettings(
      retrievalEnabled: retrievalEnabled ?? this.retrievalEnabled,
      suggestionsEnabled: suggestionsEnabled ?? this.suggestionsEnabled,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schemaVersion,
        'retrievalEnabled': retrievalEnabled,
        'suggestionsEnabled': suggestionsEnabled,
      };

  static MemorySettings fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return defaults;
    final Object? schema = value['schema'];
    if (schema is int && schema > schemaVersion) return defaults;
    return MemorySettings(
      retrievalEnabled: value['retrievalEnabled'] == true,
      suggestionsEnabled: value['suggestionsEnabled'] != false,
    );
  }
}
