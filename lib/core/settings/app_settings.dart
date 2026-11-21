import 'package:flutter/material.dart';

/// Density preference applied through ThemeData.visualDensity.
enum AuraDensity { comfortable, compact }

/// How the application selects its visual theme.
///
/// Dark is the default so existing installations keep the premium AURA look.
enum AuraThemeMode { system, dark, light }

/// Swappable AURA visual identity.
///
/// Null in [AppSettings.visualStyle] means "platform default": violet glass on
/// Android, the original midnight navy elsewhere. An explicit value is stored
/// only after the user changes it in Settings.
enum AuraVisualStyle { violet, midnight }

extension AuraVisualStyleX on AuraVisualStyle {
  String get label => switch (this) {
        AuraVisualStyle.violet => 'Violet glass',
        AuraVisualStyle.midnight => 'Midnight navy',
      };
}

/// Application UI language preference.
///
/// This is intentionally separate from [AiLanguage], which controls the
/// language of model responses. The two must not be conflated.
enum AuraLanguage { auto, english, hindi, bengali }

extension AuraThemeModeX on AuraThemeMode {
  String get label => switch (this) {
        AuraThemeMode.system => 'System',
        AuraThemeMode.dark => 'Dark',
        AuraThemeMode.light => 'Light',
      };

  ThemeMode get themeMode => switch (this) {
        AuraThemeMode.system => ThemeMode.system,
        AuraThemeMode.dark => ThemeMode.dark,
        AuraThemeMode.light => ThemeMode.light,
      };
}

extension AuraLanguageX on AuraLanguage {
  String get label => switch (this) {
        AuraLanguage.auto => 'Auto / system',
        AuraLanguage.english => 'English',
        AuraLanguage.hindi => 'हिन्दी',
        AuraLanguage.bengali => 'বাংলা',
      };

  /// Null means Follow the system locale.
  Locale? get locale => switch (this) {
        AuraLanguage.auto => null,
        AuraLanguage.english => const Locale('en'),
        AuraLanguage.hindi => const Locale('hi'),
        AuraLanguage.bengali => const Locale('bn'),
      };
}

/// Persisted, user-editable preferences for AURA Hub.
///
/// Kept immutable so Riverpod can compare values cheaply. Every field has a
/// safe default; persistence is handled by [AppSettingsController].
class AppSettings {
  const AppSettings({
    this.apiBaseUrl = defaultApiBaseUrl,
    this.pollingIntervalSeconds = defaultPollingIntervalSeconds,
    this.historyRetentionMinutes = defaultHistoryRetentionMinutes,
    this.reduceMotion = false,
    this.density = AuraDensity.comfortable,
    this.themeMode = AuraThemeMode.dark,
    this.visualStyle,
    this.language = AuraLanguage.auto,
    this.telemetryEnabled = true,
    this.launchAtStartup = false,
    this.startMinimized = false,
    this.rememberLastProfile = false,
    this.lastActiveProfile,
  });

  static const String defaultApiBaseUrl = 'http://127.0.0.1:8765';
  static const int defaultPollingIntervalSeconds = 3;
  static const int defaultHistoryRetentionMinutes = 30;
  static const int schemaVersion = 2;

  /// Supported intervals. Kept explicit so the UI cannot offer a value that
  /// would hammer the local API.
  static const List<int> supportedIntervals = <int>[1, 2, 3, 5, 10];

  /// Session-only telemetry history options. Nothing here is written to disk.
  static const List<int> supportedHistoryRetentionMinutes = <int>[10, 30, 60];

  /// Only these profile scopes may be remembered. Never store a PIN or any
  /// other authentication secret in startup or preference files.
  static const List<String> supportedProfileScopes = <String>[
    'family',
    'ayush',
  ];

  final String apiBaseUrl;
  final int pollingIntervalSeconds;
  final int historyRetentionMinutes;
  final bool reduceMotion;
  final AuraDensity density;
  final AuraThemeMode themeMode;
  final AuraVisualStyle? visualStyle;
  final AuraLanguage language;
  final bool telemetryEnabled;
  final bool launchAtStartup;
  final bool startMinimized;
  final bool rememberLastProfile;
  final String? lastActiveProfile;

  static const AppSettings defaults = AppSettings();

  /// True when the configured endpoint is on this machine. The bundled API is
  /// loopback-only and unauthenticated; a non-loopback endpoint needs a trusted
  /// network and, eventually, real authentication.
  bool get isLoopbackApi {
    final Uri? uri = Uri.tryParse(apiBaseUrl);
    if (uri == null) return false;
    final String host =
        uri.host.toLowerCase().replaceAll('[', '').replaceAll(']', '');
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }

  Duration get pollingInterval => Duration(seconds: pollingIntervalSeconds);

  /// How long successful Windows host snapshots stay in memory this session.
  Duration get historyRetention => Duration(minutes: historyRetentionMinutes);

  VisualDensity get visualDensity => density == AuraDensity.compact
      ? VisualDensity.compact
      : VisualDensity.standard;

  bool get isDefault =>
      apiBaseUrl == defaultApiBaseUrl &&
      pollingIntervalSeconds == defaultPollingIntervalSeconds &&
      historyRetentionMinutes == defaultHistoryRetentionMinutes &&
      !reduceMotion &&
      density == AuraDensity.comfortable &&
      themeMode == AuraThemeMode.dark &&
      visualStyle == null &&
      language == AuraLanguage.auto &&
      telemetryEnabled &&
      !launchAtStartup &&
      !startMinimized &&
      !rememberLastProfile &&
      lastActiveProfile == null;

  /// Normalises a stored URL so a trailing slash cannot produce `//api/system`.
  static String normaliseApiBaseUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return defaultApiBaseUrl;
    return trimmed.replaceFirst(RegExp(r'/+$'), '');
  }

  /// Returns a sanitised profile scope, or null when the value is unsupported.
  static String? normaliseProfileScope(Object? value) =>
      value is String && supportedProfileScopes.contains(value) ? value : null;

  /// Returns a user-facing validation error, or null when [value] is usable.
  ///
  /// A base URL is scheme + host + optional port only. Credentials, query
  /// strings, fragments and extra paths are rejected so diagnostics can never
  /// inherit a secret and requests always reach the documented endpoints.
  static String? validateApiBaseUrl(String value) {
    final String trimmed = value.trim();
    if (trimmed.isEmpty) return 'Enter the telemetry API address.';
    if (trimmed.contains(RegExp(r'\s'))) {
      return 'The URL cannot contain spaces.';
    }

    final Uri? uri = Uri.tryParse(trimmed);
    if (uri == null) {
      return 'Enter a valid URL such as http://127.0.0.1:8765.';
    }
    final String scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return 'Only http:// and https:// telemetry endpoints are supported.';
    }
    if (uri.host.isEmpty) return 'The URL needs a host name or IP address.';
    if (uri.hasPort && (uri.port < 1 || uri.port > 65535)) {
      return 'The URL port must be between 1 and 65535.';
    }
    if (uri.userInfo.isNotEmpty ||
        uri.query.isNotEmpty ||
        uri.fragment.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return 'Use only the API base URL: scheme, host and optional port.';
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppSettings &&
          runtimeType == other.runtimeType &&
          other.apiBaseUrl == apiBaseUrl &&
          other.pollingIntervalSeconds == pollingIntervalSeconds &&
          other.historyRetentionMinutes == historyRetentionMinutes &&
          other.reduceMotion == reduceMotion &&
          other.density == density &&
          other.themeMode == themeMode &&
          other.visualStyle == visualStyle &&
          other.language == language &&
          other.telemetryEnabled == telemetryEnabled &&
          other.launchAtStartup == launchAtStartup &&
          other.startMinimized == startMinimized &&
          other.rememberLastProfile == rememberLastProfile &&
          other.lastActiveProfile == lastActiveProfile;

  @override
  int get hashCode => Object.hash(
        apiBaseUrl,
        pollingIntervalSeconds,
        historyRetentionMinutes,
        reduceMotion,
        density,
        themeMode,
        visualStyle,
        language,
        telemetryEnabled,
        launchAtStartup,
        startMinimized,
        rememberLastProfile,
        lastActiveProfile,
      );

  AppSettings copyWith({
    String? apiBaseUrl,
    int? pollingIntervalSeconds,
    int? historyRetentionMinutes,
    bool? reduceMotion,
    AuraDensity? density,
    AuraThemeMode? themeMode,
    AuraVisualStyle? visualStyle,
    AuraLanguage? language,
    bool? telemetryEnabled,
    bool? launchAtStartup,
    bool? startMinimized,
    bool? rememberLastProfile,
    String? lastActiveProfile,
    bool clearLastActiveProfile = false,
    bool clearVisualStyle = false,
  }) {
    return AppSettings(
      apiBaseUrl: apiBaseUrl ?? this.apiBaseUrl,
      pollingIntervalSeconds:
          pollingIntervalSeconds ?? this.pollingIntervalSeconds,
      historyRetentionMinutes:
          historyRetentionMinutes ?? this.historyRetentionMinutes,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      density: density ?? this.density,
      themeMode: themeMode ?? this.themeMode,
      visualStyle: clearVisualStyle ? null : visualStyle ?? this.visualStyle,
      language: language ?? this.language,
      telemetryEnabled: telemetryEnabled ?? this.telemetryEnabled,
      launchAtStartup: launchAtStartup ?? this.launchAtStartup,
      startMinimized: startMinimized ?? this.startMinimized,
      rememberLastProfile: rememberLastProfile ?? this.rememberLastProfile,
      lastActiveProfile: clearLastActiveProfile
          ? null
          : lastActiveProfile ?? this.lastActiveProfile,
    );
  }
}
