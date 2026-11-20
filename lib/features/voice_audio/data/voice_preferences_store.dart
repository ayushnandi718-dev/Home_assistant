import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/voice_audio/domain/voice_preferences.dart';

/// Result of loading voice preferences, including controlled schema errors.
///
/// Unsupported/invalid schema versions are surfaced as controlled load errors
/// and marked write-protected so defaults are never automatically written over
/// the original file.
class VoicePreferencesLoadResult {
  const VoicePreferencesLoadResult({
    required this.preferences,
    this.writeProtected = false,
    this.error,
  });

  final VoicePreferences preferences;
  final bool writeProtected;
  final Object? error;

  bool get hasControlledError => error != null;
}

/// Persists one Voice & Audio configuration per workspace as JSON.
///
/// AYUSH and FAMILY never share a file. No credential, PIN or audio recording
/// belongs here: this store only holds ordinary preferences.
class VoicePreferencesStore {
  VoicePreferencesStore({Directory? directory, required this.profile})
      : _directory = directory ?? LocalPaths.appData(),
        _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}voice_preferences_${profile.storageScope}.json',
        );

  final AuraProfile profile;
  final Directory _directory;
  final File _file;

  String get filePath => _file.path;

  Future<VoicePreferencesLoadResult> loadWithStatus() async {
    try {
      if (!await _file.exists()) {
        return const VoicePreferencesLoadResult(
          preferences: VoicePreferences.defaults,
        );
      }
      final Object? decoded = jsonDecode(await _file.readAsString());
      return VoicePreferencesLoadResult(
        preferences: VoicePreferences.fromJson(decoded),
      );
    } on VoicePreferencesSchemaException catch (error) {
      // Controlled schema error (e.g. unsupported future/invalid version).
      // Preserve the original file: expose defaults in-memory but prevent any
      // automatic overwrite.
      return VoicePreferencesLoadResult(
        preferences: VoicePreferences.defaults,
        writeProtected: true,
        error: error,
      );
    } catch (error) {
      // Malformed/unreadable data: fall back safely without crashing. The file
      // is not overwritten automatically; a future explicit user save may write
      // valid current-schema preferences.
      return VoicePreferencesLoadResult(
        preferences: VoicePreferences.defaults,
        error: error,
      );
    }
  }

  Future<VoicePreferences> load() async => (await loadWithStatus()).preferences;

  /// Returns whether the write succeeded so the UI can report honest save state.
  Future<bool> save(VoicePreferences preferences) async {
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
