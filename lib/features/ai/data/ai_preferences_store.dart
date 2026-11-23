import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Persists non-secret AI preferences in a profile-isolated JSON file.
class AiPreferencesStore {
  AiPreferencesStore({
    Directory? directory,
    required AuraProfile profile,
  }) : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}ai_preferences_${profile.storageScope}.json',
        );

  final File _file;

  Future<AiPreferences> load() async {
    try {
      if (!await _file.exists()) return const AiPreferences();
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! Map<String, dynamic>) return const AiPreferences();
      return AiPreferences.fromJson(decoded);
    } catch (_) {
      return const AiPreferences();
    }
  }

  Future<void> save(
    AiPreferences preferences, {
    bool Function()? isWriteAllowed,
  }) async {
    if (isWriteAllowed != null && !isWriteAllowed()) return;
    try {
      await _file.parent.create(recursive: true);
      if (isWriteAllowed != null && !isWriteAllowed()) return;
      await _file.writeAsString(
        jsonEncode(preferences.toJson()),
        flush: true,
      );
    } catch (_) {
      // Keep the running app usable; the next mutation retries the write.
    }
  }
}
