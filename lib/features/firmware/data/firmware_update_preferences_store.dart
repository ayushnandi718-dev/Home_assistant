import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/firmware/domain/firmware_update_preferences.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Persists one Firmware Update configuration per workspace as JSON.
///
/// AYUSH and FAMILY never share a file. Corrupt or unreadable data falls back to
/// safe defaults. No device secret, token or downloaded payload belongs here.
class FirmwareUpdatePreferencesStore {
  FirmwareUpdatePreferencesStore({Directory? directory, required this.profile})
      : _directory = directory ?? LocalPaths.appData(),
        _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}firmware_update_preferences_${profile.storageScope}.json',
        );

  final AuraProfile profile;
  final Directory _directory;
  final File _file;

  String get filePath => _file.path;

  Future<FirmwareUpdatePreferences> load() async {
    try {
      if (!await _file.exists()) return FirmwareUpdatePreferences.defaults;
      return FirmwareUpdatePreferences.fromJson(
          jsonDecode(await _file.readAsString()));
    } catch (_) {
      return FirmwareUpdatePreferences.defaults;
    }
  }

  /// Returns whether the write succeeded so the UI can report honest save state.
  Future<bool> save(FirmwareUpdatePreferences preferences) async {
    try {
      await _directory.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(preferences.toJson()),
        flush: true,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
