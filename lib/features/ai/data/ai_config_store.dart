import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Persists a list of non-secret [AiProviderConfig] records as JSON under
/// [LocalPaths.appData].
///
/// SECURITY: this store NEVER writes API keys, tokens or any other secret.
/// Secrets must come from the environment or OS secure storage in a future
/// build; they must not be added to this file or to [AiProviderConfig.toJson].
/// A missing, corrupt or malformed file falls back to an empty list so an
/// unreadable config can never enable a provider by accident.
class AiConfigStore {
  AiConfigStore({
    Directory? directory,
    AuraProfile? profile,
    String? fileName,
  }) : this._(
          File(
            '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}${fileName ?? _scopedFileName(profile)}',
          ),
        );

  AiConfigStore._(this._file);

  static String _scopedFileName(AuraProfile? profile) => profile == null
      ? 'ai_providers.json'
      : 'ai_providers_${profile.storageScope}.json';

  final File _file;

  Future<List<AiProviderConfig>> load() async {
    try {
      if (!await _file.exists()) return const <AiProviderConfig>[];
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List<dynamic>) return const <AiProviderConfig>[];

      final List<AiProviderConfig> result = <AiProviderConfig>[];
      final Set<String> seenIds = <String>{};
      for (final Object? item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final AiProviderConfig config = AiProviderConfig.fromJson(item);
          if (config.validate() != null) continue;
          if (seenIds.add(config.id)) result.add(config);
        } on FormatException {
          // Skip one malformed record without discarding the rest.
          continue;
        }
      }
      return result;
    } catch (_) {
      return const <AiProviderConfig>[];
    }
  }

  /// Writes only the non-secret fields produced by [AiProviderConfig.toJson].
  Future<void> save(List<AiProviderConfig> configs) async {
    try {
      await _file.parent.create(recursive: true);
      await _file.writeAsString(
        jsonEncode(
          configs
              .where((AiProviderConfig config) => config.validate() == null)
              .map((AiProviderConfig config) => config.toJson())
              .toList(),
        ),
        flush: true,
      );
    } catch (_) {
      // A failed write must never break the running app; the next mutation
      // retries the save.
    }
  }

  /// Adds or replaces one config by id and returns the resulting list.
  Future<List<AiProviderConfig>> upsert(AiProviderConfig config) async {
    final List<AiProviderConfig> configs = await load();
    final List<AiProviderConfig> next = <AiProviderConfig>[
      config,
      ...configs.where(
        (AiProviderConfig item) => item.id != config.id,
      ),
    ];
    await save(next);
    return next;
  }
}
