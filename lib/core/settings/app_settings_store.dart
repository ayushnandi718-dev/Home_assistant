import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';

/// Persists [AppSettings] as JSON in a per-user local file.
///
/// Uses dart:io directly instead of a plugin: plugins require symlink support
/// (Windows Developer Mode) to build, while AURA Hub is a Windows-only app and
/// can write its own settings file natively.
class AppSettingsStore {
  AppSettingsStore({Directory? directory})
      : _directory = directory ?? defaultDirectory;

  static const String _fileName = 'app_settings.json';

  /// `%APPDATA%\AURA Hub` on Windows, with a portable fallback.
  static Directory get defaultDirectory {
    final String? appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory('$appData${Platform.pathSeparator}AURA Hub');
    }
    final String home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return Directory('$home${Platform.pathSeparator}.aura_hub');
  }

  final Directory _directory;

  Future<File> get _file async {
    await _directory.create(recursive: true);
    return File('${_directory.path}${Platform.pathSeparator}$_fileName');
  }

  /// Corrupt, missing or unreadable settings fall back to safe defaults so the
  /// app always starts.
  Future<AppSettings> load() async {
    try {
      final File file = await _file;
      if (!await file.exists()) return AppSettings.defaults;
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return AppSettings.defaults;

      final Object? rawInterval = decoded['pollingIntervalSeconds'];
      final Object? rawRetention = decoded['historyRetentionMinutes'];
      final Object? rawDensity = decoded['density'];
      final int interval = rawInterval is int
          ? rawInterval
          : AppSettings.defaultPollingIntervalSeconds;
      final int retention = rawRetention is int
          ? rawRetention
          : AppSettings.defaultHistoryRetentionMinutes;
      final int density = rawDensity is int ? rawDensity : 0;
      final String storedUrl = AppSettings.normaliseApiBaseUrl(
        decoded['apiBaseUrl'] as String? ?? AppSettings.defaultApiBaseUrl,
      );
      // A hand-edited or stale settings file must not reintroduce an unsafe
      // URL (credentials, path, query or unsupported scheme) behind the UI.
      final String apiBaseUrl =
          AppSettings.validateApiBaseUrl(storedUrl) == null
              ? storedUrl
              : AppSettings.defaultApiBaseUrl;

      return AppSettings(
        apiBaseUrl: apiBaseUrl,
        pollingIntervalSeconds:
            AppSettings.supportedIntervals.contains(interval)
                ? interval
                : AppSettings.defaultPollingIntervalSeconds,
        historyRetentionMinutes:
            AppSettings.supportedHistoryRetentionMinutes.contains(retention)
                ? retention
                : AppSettings.defaultHistoryRetentionMinutes,
        reduceMotion: decoded['reduceMotion'] is bool
            ? decoded['reduceMotion'] as bool
            : false,
        density: density == 1 ? AuraDensity.compact : AuraDensity.comfortable,
      );
    } catch (_) {
      return AppSettings.defaults;
    }
  }

  Future<void> save(AppSettings settings) async {
    final File file = await _file;
    await file.writeAsString(
      jsonEncode(<String, dynamic>{
        'apiBaseUrl': settings.apiBaseUrl,
        'pollingIntervalSeconds': settings.pollingIntervalSeconds,
        'historyRetentionMinutes': settings.historyRetentionMinutes,
        'reduceMotion': settings.reduceMotion,
        'density': settings.density == AuraDensity.compact ? 1 : 0,
      }),
      flush: true,
    );
  }
}
