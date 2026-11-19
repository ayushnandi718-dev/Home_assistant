import 'dart:io';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/memory/data/memory_settings_store.dart';
import 'package:aura_hub/features/memory/data/memory_store.dart';
import 'package:aura_hub/features/memory/data/secure_memory_file.dart';
import 'package:aura_hub/features/memory/domain/memory_record.dart';
import 'package:aura_hub/features/memory/domain/memory_settings.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Encrypted replacement for [MemoryStore] in the AYUSH workspace only.
///
/// The file name is unchanged so existing plaintext files migrate in place.
class EncryptedMemoryStore implements MemoryRecordStore {
  EncryptedMemoryStore({
    Directory? directory,
    required this.profile,
    required MemoryCipher cipher,
    Future<void> Function()? beforeMigrationCommit,
  }) : _file = SecureMemoryFile(
          file: File(
            '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
            'memory_${profile.storageScope}.json',
          ),
          scope: profile.storageScope,
          cipher: cipher,
          validatePayload: _isValidPayload,
          beforeMigrationCommit: beforeMigrationCommit,
        );

  @override
  final AuraProfile profile;

  final SecureMemoryFile _file;

  static bool _isValidPayload(Object? value) {
    if (value is List<dynamic>) return true;
    if (value is! Map<String, dynamic>) return false;
    final Object? schema = value['schema'];
    if (schema is int && schema > MemoryRecord.schemaVersion) return false;
    return value['records'] is List<dynamic>;
  }

  @override
  Future<List<MemoryRecord>> load() async {
    final Object? payload = await _file.read();
    if (payload == null) return const <MemoryRecord>[];

    final Object? rawRecords = payload is List<dynamic>
        ? payload
        : payload is Map<String, dynamic>
            ? payload['records']
            : null;
    if (rawRecords is! List<dynamic>) {
      throw const MemoryStorageException(MemoryStorageMessages.unreadable);
    }

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
  }

  @override
  Future<bool> save(List<MemoryRecord> records) async {
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

    await _file.write(<String, dynamic>{
      'schema': MemoryRecord.schemaVersion,
      'records': payload,
    });
    return true;
  }
}

/// Encrypted replacement for [MemorySettingsStore] in the AYUSH workspace.
class EncryptedMemorySettingsStore implements MemorySettingsStorage {
  EncryptedMemorySettingsStore({
    Directory? directory,
    required this.profile,
    required MemoryCipher cipher,
    Future<void> Function()? beforeMigrationCommit,
  }) : _file = SecureMemoryFile(
          file: File(
            '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
            'memory_settings_${profile.storageScope}.json',
          ),
          scope: profile.storageScope,
          cipher: cipher,
          validatePayload: _isValidPayload,
          beforeMigrationCommit: beforeMigrationCommit,
        );

  final AuraProfile profile;
  final SecureMemoryFile _file;

  static bool _isValidPayload(Object? value) {
    if (value is! Map<String, dynamic>) return false;
    final Object? schema = value['schema'];
    if (schema is int && schema > MemorySettings.schemaVersion) return false;
    return value.containsKey('retrievalEnabled') &&
        value.containsKey('suggestionsEnabled');
  }

  @override
  Future<MemorySettings> load() async {
    final Object? payload = await _file.read();
    if (payload == null) return MemorySettings.defaults;
    return MemorySettings.fromJson(payload);
  }

  @override
  Future<bool> save(MemorySettings settings) async {
    await _file.write(settings.toJson());
    return true;
  }
}
