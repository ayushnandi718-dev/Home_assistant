import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

const int _schemaVersion = 2;
const Set<String> _sensitiveMetadataKeys = <String>{
  'apikey',
  'api_key',
  'token',
  'accesstoken',
  'access_token',
  'pin',
  'secret',
  'credential',
  'password',
  'authorization',
  'diagnostic',
  'diagnostics',
  'log',
  'logs',
  'telemetry',
  'trace',
  'stacktrace',
  'stack_trace',
  'requestid',
  'request_id',
  'requestbody',
  'responsebody',
  'responseheaders',
  'response_headers',
};

/// Versioned, atomic JSON storage for shared FAMILY conversation history.
///
/// This implementation is deliberately FAMILY-only. AYUSH history uses
/// [EncryptedAiConversationStore] and must never be written through this class.
/// Legacy AYUSH plaintext is handled by that store's migration path, never by
/// an unconditional cleanup here.
class AiConversationStore implements AiConversationStorage {
  AiConversationStore({
    Directory? directory,
    required AuraProfile profile,
  })  : _profile = profile,
        _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
          'ai_conversations_${profile.storageScope}.json',
        ) {
    if (profile != AuraProfile.family) {
      throw ArgumentError.value(
        profile,
        'profile',
        'Private conversations must not use plaintext conversation storage.',
      );
    }
  }

  final AuraProfile _profile;
  final File _file;
  Future<void> _writeChain = Future<void>.value();

  /// Exposed for integrity tests that need to inspect or corrupt the file.
  File get file => _file;

  @override
  Future<AiConversationLoadResult> read() async {
    try {
      if (!await _file.exists()) {
        return AiConversationLoadResult.ready(const <AiConversation>[]);
      }
      final Object? decoded = jsonDecode(await _file.readAsString());
      final Map<String, dynamic>? envelope =
          decoded is Map<String, dynamic> ? decoded : null;
      final bool legacyList = decoded is List<dynamic>;

      if (!legacyList && envelope == null) {
        return AiConversationLoadResult.failed(
          'Conversation history had an invalid format. A fresh history was started.',
        );
      }

      if (!legacyList) {
        final Object? version = envelope!['schemaVersion'];
        if (version is! int || version > _schemaVersion || version < 1) {
          return AiConversationLoadResult.failed(
            'Conversation history uses an unsupported schema version.',
          );
        }
        final Object? scope = envelope['profile'];
        if (scope is! String || scope != _profile.storageScope) {
          return AiConversationLoadResult.failed(
            'Conversation history belongs to another profile.',
          );
        }
      }

      final Object? rawConversations = legacyList
          ? decoded
          : envelope!['conversations'] ?? envelope['items'];
      if (rawConversations is! List<dynamic>) {
        return AiConversationLoadResult.failed(
          'Conversation history was missing its conversation list.',
        );
      }

      final List<AiConversation> result = <AiConversation>[];
      final Set<String> seenIds = <String>{};
      bool recovered = legacyList;
      for (final Object? item in rawConversations) {
        if (item is! Map<String, dynamic>) {
          recovered = true;
          continue;
        }
        try {
          final AiConversation parsed = AiConversation.fromJson(item);
          if (parsed.profileScope != _profile.storageScope) {
            recovered = true;
            continue;
          }
          if (!seenIds.add(parsed.id)) {
            recovered = true;
            continue;
          }
          result.add(_normalise(parsed));
        } on FormatException {
          recovered = true;
        }
      }

      result.sort((AiConversation a, AiConversation b) =>
          b.sortTime.compareTo(a.sortTime));
      if (result.length > AuraRuntimeConfig.maxAiConversations) {
        recovered = true;
      }
      final List<AiConversation> bounded = result
          .take(AuraRuntimeConfig.maxAiConversations)
          .toList(growable: false);

      if (!recovered) {
        return AiConversationLoadResult.ready(bounded);
      }
      return AiConversationLoadResult.recovered(
        bounded,
        detail: legacyList
            ? 'Legacy conversation history was migrated to the current format.'
            : 'Some conversation records were skipped during recovery.',
      );
    } on FormatException {
      return AiConversationLoadResult.failed(
        'Conversation history was unreadable. A fresh history was started.',
      );
    } catch (_) {
      return AiConversationLoadResult.failed(
        'Conversation history could not be read. A fresh history was started.',
      );
    }
  }

  @override
  Future<void> write(List<AiConversation> conversations) {
    final Future<void> next = _writeChain.then(
      (_) => _writeUnsynchronized(conversations),
    );
    _writeChain = next.catchError((Object _) {});
    return next;
  }

  @override
  Future<void> clear() {
    final Future<void> next = _writeChain.then(
      (_) => _clearUnsynchronized(),
    );
    _writeChain = next.catchError((Object _) {});
    return next;
  }

  /// Compatibility helper for existing callers that expect a bare list.
  Future<List<AiConversation>> load() async => (await read()).conversations;

  /// Compatibility helper for existing callers that expect a bare save.
  Future<void> save(List<AiConversation> conversations) => write(conversations);

  Future<void> _writeUnsynchronized(
    List<AiConversation> conversations,
  ) async {
    final List<AiConversation> bounded = conversations
        .where((AiConversation item) {
      return item.profileScope == _profile.storageScope;
    }).toList()
      ..sort((AiConversation a, AiConversation b) =>
          b.sortTime.compareTo(a.sortTime));

    final List<AiConversation> normalised = bounded
        .take(AuraRuntimeConfig.maxAiConversations)
        .map(_normalise)
        .toList(growable: false);
    final String payload = jsonEncode(<String, dynamic>{
      'schemaVersion': _schemaVersion,
      'profile': _profile.storageScope,
      'conversations': normalised
          .map((AiConversation item) => item.toJson())
          .toList(growable: false),
    });

    final File temp = File('${_file.path}.tmp');
    final File backup = File('${_file.path}.bak');
    try {
      await _file.parent.create(recursive: true);
      if (await backup.exists()) await backup.delete();
      final bool hadOriginal = await _file.exists();
      if (hadOriginal) await _file.copy(backup.path);

      await temp.writeAsString(payload, flush: true);
      await _verify(temp, normalised.length);

      if (hadOriginal) await _file.delete();
      await temp.rename(_file.path);
      if (await backup.exists()) await backup.delete();
    } catch (error) {
      try {
        if (await _file.exists()) await _file.delete();
        if (await backup.exists()) await backup.rename(_file.path);
      } catch (_) {
        // Best-effort rollback. The original may already have been preserved.
      }
      throw AiConversationStorageException(
        'Conversation history could not be saved safely.',
      );
    } finally {
      try {
        if (await temp.exists()) await temp.delete();
      } catch (_) {
        // Temp cleanup is best-effort and never affects committed history.
      }
    }
  }

  Future<void> _clearUnsynchronized() async {
    try {
      final File temp = File('${_file.path}.tmp');
      final File backup = File('${_file.path}.bak');
      if (await _file.exists()) await _file.delete();
      if (await temp.exists()) await temp.delete();
      if (await backup.exists()) await backup.delete();
    } catch (error) {
      throw AiConversationStorageException(
        'Conversation history could not be removed safely.',
      );
    }
  }

  Future<void> _verify(File candidate, int expectedCount) async {
    final Object? decoded = jsonDecode(await candidate.readAsString());
    if (decoded is! Map<String, dynamic> ||
        decoded['schemaVersion'] != _schemaVersion ||
        decoded['profile'] != _profile.storageScope ||
        decoded['conversations'] is! List<dynamic> ||
        (decoded['conversations'] as List<dynamic>).length != expectedCount) {
      throw const FormatException('Write verification failed.');
    }
  }

  AiConversation _normalise(AiConversation conversation) {
    final List<AiMessage> messages = conversation
        .list()
        .map(
          (AiMessage message) => message.copyWith(
            conversationId: conversation.id,
            metadata: _sanitizeMetadata(message.metadata),
            delivery: message.delivery == AiMessageDelivery.streaming
                ? AiMessageDelivery.interrupted
                : message.delivery,
          ),
        )
        .toList(growable: false);
    return conversation.copyWith(messages: messages);
  }

  Map<String, String> _sanitizeMetadata(Map<String, String> metadata) {
    final Map<String, String> clean = <String, String>{};
    metadata.forEach((String key, String value) {
      final String normalisedKey = key.toLowerCase().replaceAll(
            RegExp(r'[^a-z0-9_]'),
            '',
          );
      if (normalisedKey.isEmpty || normalisedKey.length > 48) return;
      if (_sensitiveMetadataKeys.contains(normalisedKey)) return;
      if (value.length > 240) return;
      clean[key] = value;
    });
    return Map<String, String>.unmodifiable(clean);
  }
}

/// Session-only storage for AYUSH conversations in Phase 5A.
///
/// This class has no `dart:io` dependency and no file path. Phase 5B adds
/// encrypted persistence by supplying a different [AiConversationStorage].
class InMemoryAiConversationStorage implements AiConversationStorage {
  List<AiConversation> _conversations = const <AiConversation>[];

  @override
  Future<AiConversationLoadResult> read() async =>
      AiConversationLoadResult.ready(_conversations);

  @override
  Future<void> write(List<AiConversation> conversations) async {
    _conversations = List<AiConversation>.unmodifiable(conversations);
  }

  @override
  Future<void> clear() async {
    _conversations = const <AiConversation>[];
  }
}
