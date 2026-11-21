import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:flutter/services.dart';

/// Bridge to the Android app-private storage directory.
///
/// Android does not expose `APPDATA`, `USERPROFILE` or a usable `HOME` to the
/// Flutter process. The native side supplies `Context.noBackupFilesDir`, so all
/// local stores stay inside this app's sandbox instead of falling back to the
/// process working directory (`/`).
abstract final class AppStorageChannel {
  static const MethodChannel _channel = MethodChannel('aura_hub/storage');

  static Future<Directory> appDataDirectory() async {
    if (!Platform.isAndroid) {
      throw UnsupportedError(
        'Native app-private storage is only used on Android.',
      );
    }

    final String? path = await _channel.invokeMethod<String>(
      'getAppDataDirectory',
    );
    if (path == null || path.trim().isEmpty) {
      throw StateError('Android app-private storage path was empty.');
    }

    final Directory directory = Directory(path);
    await directory.create(recursive: true);
    return directory;
  }
}
