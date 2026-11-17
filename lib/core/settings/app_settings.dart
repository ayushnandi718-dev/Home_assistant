import 'package:flutter/material.dart';

/// Density preference applied through ThemeData.visualDensity.
enum AuraDensity { comfortable, compact }

/// Persisted, user-editable preferences for AURA Hub.
///
/// Kept immutable so Riverpod can compare values cheaply. Every field has a
/// safe default; persistence is handled by [AppSettingsController].
class AppSettings {
  const AppSettings({
    this.apiBaseUrl = defaultApiBaseUrl,
    this.pollingIntervalSeconds = defaultPollingIntervalSeconds,
    this.reduceMotion = false,
    this.density = AuraDensity.comfortable,
  });

  static const String defaultApiBaseUrl = 'http://127.0.0.1:8765';
  static const int defaultPollingIntervalSeconds = 3;

  /// Supported intervals. Kept explicit so the UI cannot offer a value that
  /// would hammer the local API.
  static const List<int> supportedIntervals = <int>[1, 2, 3, 5, 10];

  final String apiBaseUrl;
  final int pollingIntervalSeconds;
  final bool reduceMotion;
  final AuraDensity density;

  static const AppSettings defaults = AppSettings();

  Duration get pollingInterval => Duration(seconds: pollingIntervalSeconds);

  VisualDensity get visualDensity => density == AuraDensity.compact
      ? VisualDensity.compact
      : VisualDensity.standard;

  bool get isDefault =>
      apiBaseUrl == defaultApiBaseUrl &&
      pollingIntervalSeconds == defaultPollingIntervalSeconds &&
      !reduceMotion &&
      density == AuraDensity.comfortable;

  /// Normalises a stored URL so a trailing slash cannot produce `//api/system`.
  static String normaliseApiBaseUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return defaultApiBaseUrl;
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          other.apiBaseUrl == apiBaseUrl &&
          other.pollingIntervalSeconds == pollingIntervalSeconds &&
          other.reduceMotion == reduceMotion &&
          other.density == density;

  @override
  int get hashCode =>
      Object.hash(apiBaseUrl, pollingIntervalSeconds, reduceMotion, density);

  AppSettings copyWith({
    String? apiBaseUrl,
    int? pollingIntervalSeconds,
    bool? reduceMotion,
    AuraDensity? density,
  }) {
    return AppSettings(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      density: density ?? this.density,
    );
  }
}
