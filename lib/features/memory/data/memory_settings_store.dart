import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Per-profile persistence for memory retrieval and suggestion switches.
class MemorySettingsStore {
  MemorySettingsStore({
    Directory? directory,
    required AuraProfile profile,
  }) : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
          'memory_settings_${profile.storageScope}.json',
        );

  final File _file;

  Future<MemorySettings> load() async {
    try {
      if (!await _file.exists()) return MemorySettings.defaults;
      return MemorySettings.fromJson(jsonDecode(await _file.readAsString()));
    } catch (_) {
      return MemorySettings.defaults;
    }
  }

  Future<bool> save(MemorySettings settings) async {
    final File temp = File('${_file.path}.tmp');
    try {
      await _file.parent.create(recursive: true);
      await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
      try {
        await temp.rename(_file.path);
      } on FileSystemException {
        if (await _file.exists()) await _file.delete();
        await temp.rename(_file.path);
      }
      return true;
    } catch (_) {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Best-effort cleanup only.
      }
      return false;
    }
  }
}
