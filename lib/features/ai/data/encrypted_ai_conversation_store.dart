import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/ai/data/ai_conversation_storage_envelope.dart';
import 'package:aura_hub/features/ai/data/secure_ai_conversation_file.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/memory/data/memory_cipher.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

const int _encryptedPayloadSchema = 1;

/// Mirrors the FAMILY store's presentation-only metadata filter. It is kept
/// here so FAMILY persistence code does not need to change for Phase 5B.
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

/// DPAPI-encrypted, persistent conversation storage for the AYUSH profile.
///
/// Implements the unchanged [AiConversationStorage] boundary. FAMILY continues
/// to use [AiConversationStore]; the two profiles never share a writable file.
/// Integrity failures are sticky: once the file cannot be trusted, reads return
/// a fixed error and every write is blocked instead of replacing ciphertext.
class EncryptedAiConversationStore implements AiConversationStorage {
  EncryptedAiConversationStore({
    Directory? directory,
    required this.profile,
    required MemoryCipher cipher,
    this.isWriteAllowed,
    Future<void> Function()? beforeMigrationCommit,
    Future<void> Function()? beforeWriteCommit,
    Future<void> Function()? beforeReadCommit,
  })  : assert(profile == AuraProfile.ayush),
        _file = SecureAiConversationFile(
          file: File(
            '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}'
            '${AiConversationStorageEnvelope.fileName}',
          ),
          legacyFiles: AiConversationStorageEnvelope.legacyFileNames
              .map(
                (String name) => File(
                  '${(directory ?? LocalPaths.appData()).path}'
                  '${Platform.pathSeparator}$name',
                ),
              )
              .toList(growable: false),
          scope: profile.storageScope,
          cipher: cipher,
          validatePayload: _isValidPayload,
          normaliseLegacy: _normaliseLegacy,
          beforeMigrationCommit: beforeMigrationCommit,
          beforeWriteCommit: beforeWriteCommit,
          beforeReadCommit: beforeReadCommit,
        );

  final AuraProfile profile;
  final SecureAiConversationFile _file;

  /// Checked again immediately before every commit so a lock or profile switch
  /// that happens during an async encryption cannot update a private file.
  final bool Function()? isWriteAllowed;

  bool _blocked = false;
  int _epoch = 0;
  Future<void> _operationChain = Future<void>.value();

  @override
  Future<AiConversationLoadResult> read() => _exclusive(_readUnsynchronized);

  Future<AiConversationLoadResult> _readUnsynchronized() async {
    final int epoch = _epoch;
    if (_blocked) {
      return AiConversationLoadResult.failed(
        AiConversationStorageMessages.decryption,
      );
    }
    try {
      final Object? payload = await _file.read();
      if (epoch != _epoch) {
        return AiConversationLoadResult.failed(
          AiConversationStorageMessages.stale,
        );
      }
      if (payload == null) {
        return AiConversationLoadResult.ready(const <AiConversation>[]);
      }
      final Object? raw =
          payload is Map<String, dynamic> ? payload['conversations'] : null;
      if (raw is! List<dynamic>) {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.decryption,
        );
      }
      final List<AiConversation> conversations = <AiConversation>[];
      final Set<String> seenIds = <String>{};
      for (final Object? item in raw) {
        if (item is! Map<String, dynamic>) continue;
        final AiConversation parsed = AiConversation.fromJson(item);
        if (parsed.profileScope != profile.storageScope) continue;
        if (!seenIds.add(parsed.id)) continue;
        conversations.add(parsed);
      }
      conversations.sort((AiConversation a, AiConversation b) =>
          b.sortTime.compareTo(a.sortTime));
      final List<AiConversation> bounded = conversations
          .take(AuraRuntimeConfig.maxAiConversations)
          .toList(growable: false);
      return AiConversationLoadResult.ready(bounded);
    } on AiConversationStorageException catch (error) {
      _block();
      return AiConversationLoadResult.failed(error.message);
    } catch (_) {
      _block();
      return AiConversationLoadResult.failed(
        AiConversationStorageMessages.unreadable,
      );
    }
  }

  @override
  Future<void> write(List<AiConversation> conversations) =>
      _exclusive(() => _writeUnsynchronized(conversations));

  /// Reads and writes share one queue so a migration or interrupted commit is
  /// never observed half-finished by a concurrent load.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final Future<T> next = _operationChain.then((_) => action());
    _operationChain = next.then<void>(
      (_) {},
      onError: (Object _) {},
    );
    return next;
  }

  /// Lock/profile-switch invalidation must never delete encrypted history.
  /// It only clears this instance's transient state and invalidates writes.
  @override
  Future<void> clear() async {
    _epoch++;
  }

  Future<void> _writeUnsynchronized(List<AiConversation> conversations) async {
    if (_blocked) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.decryption,
      );
    }
    final int epoch = _epoch;
    _requireWriteAccess();

    final List<AiConversation> normalised = _normalise(conversations);
    final Map<String, dynamic> payload = <String, dynamic>{
      'schema': _encryptedPayloadSchema,
      'conversations': normalised
          .map((AiConversation item) => item.toJson())
          .toList(growable: false),
    };

    try {
      await _file.write(
        payload,
        beforeCommit: () async {
          if (epoch != _epoch) {
            throw const AiConversationStorageException(
              AiConversationStorageMessages.stale,
            );
          }
          _requireWriteAccess();
        },
      );
    } on AiConversationStorageException catch (error) {
      if (error.message == AiConversationStorageMessages.decryption ||
          error.message == AiConversationStorageMessages.unreadable) {
        _block();
      }
      rethrow;
    }
  }

  void _requireWriteAccess() {
    if (isWriteAllowed?.call() == false) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.locked,
      );
    }
  }

  void _block() {
    _blocked = true;
    _epoch++;
  }

  static bool _isValidPayload(Object? value) {
    if (value is! Map<String, dynamic>) return false;
    if (value['schema'] != _encryptedPayloadSchema) return false;
    final Object? raw = value['conversations'];
    if (raw is! List<dynamic>) return false;
    if (raw.length > AuraRuntimeConfig.maxAiConversations) return false;
    final Set<String> seenIds = <String>{};
    for (final Object? item in raw) {
      if (item is! Map<String, dynamic>) return false;
      if (item['profileScope'] != AuraProfile.ayush.storageScope) return false;
      if (_hasForeignScope(item, AuraProfile.ayush.storageScope)) return false;
      final Object? id = item['id'];
      if (id is! String || id.isEmpty || !seenIds.add(id)) return false;
      final Object? messages = item['messages'];
      if (messages is! List<dynamic>) return false;
      if (messages.length > AuraRuntimeConfig.maxConversationMessages) {
        return false;
      }
      final Set<String> seenMessageIds = <String>{};
      for (final Object? message in messages) {
        if (message is! Map<String, dynamic>) return false;
        final Object? content = message['content'];
        final Object? role = message['role'];
        final Object? timestamp = message['timestamp'];
        if (content is! String || role is! String) return false;
        if (!AiMessageRole.values
            .any((AiMessageRole item) => item.name == role)) {
          return false;
        }
        if (timestamp is! String || DateTime.tryParse(timestamp) == null) {
          return false;
        }
        final Object? delivery = message['delivery'];
        if (delivery != null) {
          if (delivery is! String ||
              !AiMessageDelivery.values
                  .any((AiMessageDelivery item) => item.name == delivery)) {
            return false;
          }
        }
        final Object? metadata = message['metadata'];
        if (metadata != null && metadata is! Map<String, dynamic>) return false;
        final Object? messageId = message['id'];
        if (messageId != null) {
          if (messageId is! String ||
              messageId.isEmpty ||
              !seenMessageIds.add(messageId)) {
            return false;
          }
        }
        final Object? conversationId = message['conversationId'];
        if (conversationId != null && conversationId != id) return false;
      }
    }
    return true;
  }

  static bool _hasForeignScope(Map<String, dynamic> item, String expected) {
    const List<String> scopeKeys = <String>['profileScope', 'scope', 'profile'];
    for (final String key in scopeKeys) {
      final Object? value = item[key];
      if (value != null && value != expected) return true;
    }
    return false;
  }

  /// Legacy parsing in the domain model silently deduplicates message ids.
  /// Migration must reject duplicates instead, so the original can be reviewed.
  static bool _hasInvalidMessages(Map<String, dynamic> item, String id) {
    final Object? raw = item['messages'];
    if (raw is! List<dynamic>) return true;
    if (raw.length > AuraRuntimeConfig.maxConversationMessages) return true;
    final Set<String> seenIds = <String>{};
    for (final Object? message in raw) {
      if (message is! Map<String, dynamic>) return true;
      if (message['content'] is! String || message['role'] is! String) {
        return true;
      }
      final Object? timestamp = message['timestamp'];
      if (timestamp is! String || DateTime.tryParse(timestamp) == null) {
        return true;
      }
      final Object? messageId = message['id'];
      if (messageId != null &&
          (messageId is! String ||
              messageId.isEmpty ||
              !seenIds.add(messageId))) {
        return true;
      }
      final Object? conversationId = message['conversationId'];
      if (conversationId != null && conversationId != id) return true;
    }
    return false;
  }

  /// Validates and stamps legacy plaintext before it is ever encrypted.
  /// Legacy records had no profile field, so the AYUSH filename supplies the
  /// scope; any explicit foreign scope rejects the whole migration.
  static Object? _normaliseLegacy(Object? decoded) {
    final List<dynamic> items;
    if (decoded is List<dynamic>) {
      items = decoded;
    } else if (decoded is Map<String, dynamic>) {
      final Object? version = decoded['schemaVersion'];
      if (version is! int || version < 1 || version > 2) {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.migration,
        );
      }
      if (_hasForeignScope(decoded, AuraProfile.ayush.storageScope)) {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.migration,
        );
      }
      final Object? raw = decoded['conversations'] ?? decoded['items'];
      if (raw is! List<dynamic>) {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.migration,
        );
      }
      items = raw;
    } else {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.migration,
      );
    }
    if (items.length > AuraRuntimeConfig.maxAiConversations) {
      throw const AiConversationStorageException(
        AiConversationStorageMessages.migration,
      );
    }

    final List<AiConversation> conversations = <AiConversation>[];
    final Set<String> seenIds = <String>{};
    for (final Object? item in items) {
      if (item is! Map<String, dynamic>) {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.migration,
        );
      }
      if (_hasForeignScope(item, AuraProfile.ayush.storageScope)) {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.migration,
        );
      }
      final Object? id = item['id'];
      if (id is! String || id.isEmpty || !seenIds.add(id)) {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.migration,
        );
      }
      if (_hasInvalidMessages(item, id)) {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.migration,
        );
      }
      final Map<String, dynamic> scoped = Map<String, dynamic>.from(item)
        ..['profileScope'] = AuraProfile.ayush.storageScope;
      final AiConversation parsed;
      try {
        parsed = AiConversation.fromJson(scoped);
      } on FormatException {
        throw const AiConversationStorageException(
          AiConversationStorageMessages.migration,
        );
      }
      conversations.add(parsed);
    }

    final List<AiConversation> normalised = _normalise(conversations);
    return <String, dynamic>{
      'schema': _encryptedPayloadSchema,
      'conversations': normalised
          .map((AiConversation item) => item.toJson())
          .toList(growable: false),
    };
  }

  static List<AiConversation> _normalise(List<AiConversation> conversations) {
    final List<AiConversation> filtered = conversations
        .where((AiConversation item) {
      return item.profileScope == AuraProfile.ayush.storageScope;
    }).toList()
      ..sort((AiConversation a, AiConversation b) =>
          b.sortTime.compareTo(a.sortTime));

    final Set<String> seenIds = <String>{};
    final List<AiConversation> result = <AiConversation>[];
    for (final AiConversation conversation in filtered) {
      if (!seenIds.add(conversation.id)) continue;
      if (result.length >= AuraRuntimeConfig.maxAiConversations) break;
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
      result.add(conversation.copyWith(messages: messages));
    }
    return List<AiConversation>.unmodifiable(result);
  }

  static Map<String, String> _sanitizeMetadata(Map<String, String> metadata) {
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
