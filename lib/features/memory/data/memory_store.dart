import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Persistence boundary used by the memory repository.
///
/// Implementations are fixed to one profile at construction. This prevents a
/// repository from being rebound to another workspace at runtime.
abstract class MemoryRecordStore {
  AuraProfile get profile;

  Future<List<MemoryRecord>> load({bool Function()? isWriteAllowed});
  Future<bool> save(
    List<MemoryRecord> records, {
    bool Function()? isWriteAllowed,
  });
}

/// Versioned local JSON storage for one profile's memories.
///
/// The scope is fixed at construction. There is no global memory file, so the
/// FAMILY workspace cannot load AYUSH records even by mistake. Writes use a
/// sibling temporary file where the platform allows it; a failed write returns
/// false instead of claiming the data was saved.
///
/// This plaintext implementation remains the FAMILY store. AYUSH uses
/// [EncryptedMemoryStore] through the same interface.
class MemoryStore implements MemoryRecordStore {
  MemoryStore({
    Directory? directory,
    required AuraProfile profile,
  })  : profile = profile,
        _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
          'memory_${profile.storageScope}.json',
        );

  @override
  final AuraProfile profile;

  final File _file;

  @override
  Future<List<MemoryRecord>> load({bool Function()? isWriteAllowed}) async {
    try {
      if (!await _file.exists()) return const <MemoryRecord>[];
      final Object? decoded = jsonDecode(await _file.readAsString());
      final Object? rawRecords = decoded is Map<String, dynamic>
          ? decoded['records']
          : decoded is List<dynamic>
              ? decoded
              : null;
      if (rawRecords is! List<dynamic>) return const <MemoryRecord>[];

      final List<MemoryRecord> result = <MemoryRecord>[];
      final Set<String> seenIds = <String>{};
      for (final Object? item in rawRecords) {
        final MemoryRecord? record =
            MemoryRecord.tryFromJson(item, profile: profile);
        if (record == null || !seenIds.add(record.id)) continue;
        if (result.length >= AuraRuntimeConfig.maxMemoryRecords) break;
        result.add(record);
      }
      return List<MemoryRecord>.unmodifiable(result);
    } catch (_) {
      // Corrupt files are recoverable by starting empty; unrelated scopes use
      // separate files and are never touched.
      return const <MemoryRecord>[];
    }
  }

  @override
  Future<bool> save(
    List<MemoryRecord> records, {
    bool Function()? isWriteAllowed,
  }) async {
    if (isWriteAllowed != null && !isWriteAllowed()) return false;
    final File temp = File('${_file.path}.tmp');
    try {
      await _file.parent.create(recursive: true);
      final Set<String> seenIds = <String>{};
      final List<Map<String, dynamic>> payload = <Map<String, dynamic>>[];
      for (final MemoryRecord record in records) {
        if (record.profile != profile ||
            record.validationError != null ||
            !seenIds.add(record.id)) {
          continue;
        }
        if (payload.length >= AuraRuntimeConfig.maxMemoryRecords) break;
        payload.add(record.toJson());
      }

      await temp.writeAsString(
        jsonEncode(<String, dynamic>{
          'schema': MemoryRecord.schemaVersion,
          'records': payload,
        }),
        flush: true,
      );
      if (isWriteAllowed != null && !isWriteAllowed()) {
        await temp.delete();
        return false;
      }
      try {
        await temp.rename(_file.path);
      } on FileSystemException {
        // Windows may refuse rename over an existing file. Remove the old
        // target only after the complete temporary file has been written.
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
