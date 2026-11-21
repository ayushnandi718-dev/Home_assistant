import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/platform/app_storage_channel.dart';

/// Per-user AURA Hub data paths.
///
/// The legacy Windows environment-based paths are preserved. Android receives
/// an app-private directory from the native side during startup; there is
/// deliberately no portable `.` fallback there because the working directory
/// is not writable and would make local persistence fail at runtime.
abstract final class LocalPaths {
  static Directory? _androidAppData;
  static Directory? _testAppData;

  /// Resolves platform-specific storage before any local store is created.
  static Future<void> initialize() async {
    if (!Platform.isAndroid || _androidAppData != null) return;
    _androidAppData = await AppStorageChannel.appDataDirectory();
  }

  /// Per-user AURA Hub data directory.
  static Directory appData() {
    final Directory? resolved = _testAppData ?? _androidAppData;
    if (resolved != null) return resolved;

    if (Platform.isAndroid) {
      throw StateError(
        'LocalPaths.initialize() must complete before app data is accessed.',
      );
    }

    final String? appData = Platform.environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      return Directory('$appData${Platform.pathSeparator}AURA Hub');
    }
    final String home = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        '.';
    return Directory('$home${Platform.pathSeparator}.aura_hub');
  }

  /// Prefers the user's Documents folder, falling back to the profile root and
  /// finally the current directory. Callers still handle write failures.
  static Future<Directory> documents() async {
    if (Platform.isAndroid) return appData();
    final String? profile = Platform.environment['USERPROFILE'];
    if (profile != null && profile.isNotEmpty) {
      final Directory documents = Directory(
        '$profile${Platform.pathSeparator}Documents',
      );
      if (await documents.exists()) return documents;
      return Directory(profile);
    }
    return Directory.current;
  }

  /// Injects a resolved app-data directory in tests.
  static void setAppDataDirectoryForTesting(Directory? directory) {
    _testAppData = directory;
  }
}
