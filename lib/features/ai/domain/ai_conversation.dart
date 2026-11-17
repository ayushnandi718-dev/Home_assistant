import 'package:aura_hub/core/config/aura_runtime_config.dart';

/// Who produced a message in an AI conversation transcript.
enum AiMessageRole { system, user, assistant, tool }

/// One immutable transcript entry.
///
/// Content is only ever supplied by the caller. This foundation never creates
/// assistant or tool content on its own.
class AiMessage {
  const AiMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCallId,
  });

  final AiMessageRole role;
  final String content;
  final DateTime timestamp;
  final String? toolCallId;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (toolCallId != null) 'toolCallId': toolCallId,
      };

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    final AiMessageRole role = AiMessageRole.values.firstWhere(
      (AiMessageRole item) => item.name == json['role'],
      orElse: () => AiMessageRole.user,
    );
    return AiMessage(
      role: role,
      content: (json['content'] as String?) ?? '',
      timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      toolCallId: json['toolCallId'] as String?,
    );
  }
}

/// An immutable, bounded in-memory conversation transcript.
///
/// History is capped by [AuraRuntimeConfig.maxConversationMessages] so a
/// long-running desktop app cannot grow memory without limit. Nothing here
/// performs inference or invokes a model.
class AiConversation {
  const AiConversation({
    this.id = 'default',
    List<AiMessage> messages = const <AiMessage>[],
  }) : _messages = messages;

  final String id;
  final List<AiMessage> _messages;

  /// Returns an unmodifiable view of the transcript, oldest first.
  List<AiMessage> list() => List<AiMessage>.unmodifiable(_messages);

  int get length => _messages.length;
  bool get isEmpty => _messages.isEmpty;
  bool get isNotEmpty => _messages.isNotEmpty;

  /// Appends a caller-supplied message, dropping the oldest entries when the
  /// configured bound is exceeded.
  AiConversation append(AiMessage message) {
    final List<AiMessage> combined = <AiMessage>[..._messages, message];
    final int limit = AuraRuntimeConfig.maxConversationMessages;
    final List<AiMessage> kept = combined.length > limit
        ? combined.sublist(combined.length - limit)
        : combined;
    return AiConversation(
      id: id,
      messages: List<AiMessage>.unmodifiable(kept),
    );
  }

  /// Returns a fresh empty conversation with the same id.
  AiConversation clear() => AiConversation(id: id);
}
