import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Persists one Display Studio configuration per workspace as JSON.
///
/// AYUSH and FAMILY never share a file. Corrupt or unreadable data falls back to
/// safe defaults instead of crashing the app. No secret belongs in this file.
class DisplayPreferencesStore {
  DisplayPreferencesStore({Directory? directory, required this.profile})
      : _directory = directory ?? LocalPaths.appData(),
        _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}display_preferences_${profile.storageScope}.json',
        );

  final AuraProfile profile;
  final Directory _directory;
  final File _file;

  String get filePath => _file.path;

  Future<DisplayPreferences> load() async {
    try {
      if (!await _file.exists()) return DisplayPreferences.defaults;
      return DisplayPreferences.fromJson(
          jsonDecode(await _file.readAsString()));
    } catch (_) {
      return DisplayPreferences.defaults;
    }
  }

  /// Returns whether the write succeeded so the UI can report honest save state.
  Future<bool> save(DisplayPreferences preferences) async {
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
