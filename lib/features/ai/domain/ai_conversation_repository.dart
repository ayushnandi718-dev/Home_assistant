import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// How a conversation snapshot was obtained from storage.
enum AiConversationLoadOutcome {
  /// The snapshot came from a valid store.
  ready,

  /// The snapshot was recovered from a legacy or partially invalid store.
  recovered,

  /// The snapshot could not be trusted and an empty result was returned.
  failed,
}

/// A profile-scoped conversation snapshot plus its integrity status.
class AiConversationLoadResult {
  const AiConversationLoadResult({
    required this.conversations,
    required this.outcome,
    this.detail,
  });

  factory AiConversationLoadResult.ready(
    List<AiConversation> conversations,
  ) =>
      AiConversationLoadResult(
        conversations: conversations,
        outcome: AiConversationLoadOutcome.ready,
      );

  factory AiConversationLoadResult.recovered(
    List<AiConversation> conversations, {
    required String detail,
  }) =>
      AiConversationLoadResult(
        conversations: conversations,
        outcome: AiConversationLoadOutcome.recovered,
        detail: detail,
      );

  factory AiConversationLoadResult.failed(String detail) =>
      AiConversationLoadResult(
        conversations: const <AiConversation>[],
        outcome: AiConversationLoadOutcome.failed,
        detail: detail,
      );

  final List<AiConversation> conversations;
  final AiConversationLoadOutcome outcome;
  final String? detail;
}

/// Raised by storage implementations when a write cannot be completed safely.
class AiConversationStorageException implements Exception {
  const AiConversationStorageException(this.message);

  final String message;

  @override
  String toString() => 'AiConversationStorageException: $message';
}

/// The narrow data boundary used by the conversation repository.
///
/// Implementations must never infer a profile from a file path or accept data
/// belonging to another scope. The profile-bound repository performs the final
/// ownership validation before any storage implementation is called.
abstract class AiConversationStorage {
  Future<AiConversationLoadResult> read();

  Future<void> write(List<AiConversation> conversations);

  /// Invalidates this storage instance's cached or decrypted snapshot.
  ///
  /// FAMILY lock handling must not call this: FAMILY history is intentionally
  /// persisted. AYUSH lock handling calls it to clear decrypted state without
  /// deleting the encrypted file.
  Future<void> clear();
}

/// Profile-aware conversation boundary used by controllers and UI.
abstract class AiConversationRepository {
  AuraProfile get profile;

  Future<AiConversationLoadResult> load();

  Future<void> save(List<AiConversation> conversations);

  /// Clears private in-memory session data. Never exposed as a UI "delete".
  Future<void> clearSession();
}

/// Binds one storage instance to one profile and checks access on every read
/// and write. AYUSH is backed by a DPAPI-encrypted store and FAMILY by a
/// plaintext store without changing this class, the domain models, or the UI.
class ProfileBoundAiConversationRepository implements AiConversationRepository {
  ProfileBoundAiConversationRepository({
    required this.profile,
    required AiConversationStorage storage,
    required ProfileAccessReader accessReader,
  })  : _storage = storage,
        _accessReader = accessReader;

  @override
  final AuraProfile profile;

  final AiConversationStorage _storage;
  final ProfileAccessReader _accessReader;

  @override
  Future<AiConversationLoadResult> load() {
    _requireAccess();
    return _storage.read();
  }

  @override
  Future<void> save(List<AiConversation> conversations) {
    _requireAccess();
    for (final AiConversation conversation in conversations) {
      if (conversation.profileScope != profile.storageScope) {
        throw ArgumentError(
          'Conversation ${conversation.id} belongs to '
          '${conversation.profileScope}, not ${profile.storageScope}.',
        );
      }
    }
    return _storage.write(conversations);
  }

  @override
  Future<void> clearSession() {
    // Clearing is intentionally allowed without a private-read guard: this is
    // the operation invoked by lock handling and must work even when access
    // has already been revoked.
    return _storage.clear();
  }

  void _requireAccess() {
    _accessReader().requirePrivate(profile, true);
  }
}

/// Presentation-level view of the last repository load/write outcome.
enum AiConversationLoadPhase { idle, loading, ready, recovered, failed }

class AiConversationRecoveryState {
  const AiConversationRecoveryState({
    this.phase = AiConversationLoadPhase.idle,
    this.message,
    this.version = 0,
  });

  final AiConversationLoadPhase phase;
  final String? message;
  final int version;

  AiConversationRecoveryState next({
    required AiConversationLoadPhase phase,
    String? message,
  }) {
    return AiConversationRecoveryState(
      phase: phase,
      message: message,
      version: version + 1,
    );
  }
}
