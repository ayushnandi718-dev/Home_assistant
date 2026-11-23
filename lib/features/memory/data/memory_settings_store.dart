import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Persistence boundary for per-profile retrieval and suggestion switches.
abstract class MemorySettingsStorage {
  Future<MemorySettings> load({bool Function()? isWriteAllowed});
  Future<bool> save(
    MemorySettings settings, {
    bool Function()? isWriteAllowed,
  });
}

/// Plaintext per-profile persistence.
///
/// This remains the FAMILY implementation. AYUSH uses
/// [EncryptedMemorySettingsStore] through the same interface.
class MemorySettingsStore implements MemorySettingsStorage {
  MemorySettingsStore({
    Directory? directory,
    required AuraProfile profile,
  }) : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
          'memory_settings_${profile.storageScope}.json',
        );

  final File _file;

  @override
  Future<MemorySettings> load({bool Function()? isWriteAllowed}) async {
    try {
      if (!await _file.exists()) return MemorySettings.defaults;
      return MemorySettings.fromJson(jsonDecode(await _file.readAsString()));
    } catch (_) {
      return MemorySettings.defaults;
    }
  }

  @override
  Future<bool> save(
    MemorySettings settings, {
    bool Function()? isWriteAllowed,
  }) async {
    if (isWriteAllowed != null && !isWriteAllowed()) return false;
    final File temp = File('${_file.path}.tmp');
    try {
      await _file.parent.create(recursive: true);
      await temp.writeAsString(jsonEncode(settings.toJson()), flush: true);
      if (isWriteAllowed != null && !isWriteAllowed()) {
        await temp.delete();
        return false;
      }
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
