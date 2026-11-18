import 'package:aura_hub/core/config/aura_runtime_config.dart';

/// Who produced a message in an AI conversation transcript.
enum AiMessageRole { system, user, assistant, tool }

/// One immutable transcript entry.
///
/// Content is supplied by the caller: the domain model never invents assistant
/// output. [isInterrupted] marks real partial model output that was cancelled
/// or cut short, so the UI can be honest about its incomplete state.
class AiMessage {
  const AiMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.toolCallId,
    this.isInterrupted = false,
  });

  final AiMessageRole role;
  final String content;
  final DateTime timestamp;
  final String? toolCallId;
  final bool isInterrupted;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (toolCallId != null) 'toolCallId': toolCallId,
        if (isInterrupted) 'interrupted': true,
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
      isInterrupted: json['interrupted'] == true,
    );
  }
}

/// An immutable, bounded conversation transcript with local metadata.
///
/// History is capped by [AuraRuntimeConfig.maxConversationMessages] so a
/// long-running desktop app cannot grow memory without limit. Persistence is
/// handled by stores in the data layer; this model contains no inference.
class AiConversation {
  const AiConversation({
    this.id = 'default',
    List<AiMessage> messages = const <AiMessage>[],
    this.title,
    this.createdAt,
    this.updatedAt,
  }) : _messages = messages;

  final String id;
  final List<AiMessage> _messages;
  final String? title;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Returns an unmodifiable view of the transcript, oldest first.
  List<AiMessage> list() => List<AiMessage>.unmodifiable(_messages);

  int get length => _messages.length;
  bool get isEmpty => _messages.isEmpty;
  bool get isNotEmpty => _messages.isNotEmpty;

  /// A stable display title, derived from the first user message when needed.
  String get displayTitle {
    final String? explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    for (final AiMessage message in _messages) {
      if (message.role == AiMessageRole.user) {
        final String firstLine =
            message.content.trim().split(RegExp(r'\s+')).take(6).join(' ');
        if (firstLine.isNotEmpty) return firstLine;
      }
    }
    return 'New conversation';
  }

  DateTime get sortTime =>
      updatedAt ??
      (_messages.isEmpty
          ? createdAt ?? DateTime.fromMillisecondsSinceEpoch(0)
          : _messages.last.timestamp);

  AiConversation copyWith({
    String? id,
    List<AiMessage>? messages,
    String? title,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool clearTitle = false,
  }) {
    return AiConversation(
      id: id ?? this.id,
      messages: messages ?? _messages,
      title: clearTitle ? null : title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Appends a caller-supplied message, dropping the oldest entries when the
  /// configured bound is exceeded.
  AiConversation append(AiMessage message) {
    final List<AiMessage> combined = <AiMessage>[..._messages, message];
    final int limit = AuraRuntimeConfig.maxConversationMessages;
    final List<AiMessage> kept = combined.length > limit
        ? combined.sublist(combined.length - limit)
        : combined;
    return copyWith(
      messages: List<AiMessage>.unmodifiable(kept),
      createdAt: createdAt ?? message.timestamp,
      updatedAt: message.timestamp,
    );
  }

  /// Returns a fresh empty conversation with the same id and metadata.
  AiConversation clear() => AiConversation(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        if (title != null) 'title': title,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'messages': _messages
            .map((AiMessage message) => message.toJson())
            .toList(growable: false),
      };

  factory AiConversation.fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Conversation id is missing.');
    }
    final List<AiMessage> messages = <AiMessage>[];
    final Object? rawMessages = json['messages'];
    if (rawMessages is List<dynamic>) {
      for (final Object? item in rawMessages) {
        if (item is Map<String, dynamic>) {
          messages.add(AiMessage.fromJson(item));
        }
      }
    }
    return AiConversation(
      id: id,
      title: json['title'] as String?,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? ''),
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
      messages: List<AiMessage>.unmodifiable(messages),
    );
  }
}
