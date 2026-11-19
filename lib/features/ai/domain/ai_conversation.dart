import 'package:aura_hub/core/config/aura_runtime_config.dart';

/// Who produced a message in an AI conversation transcript.
enum AiMessageRole { system, user, assistant, tool }

/// Delivery state recorded for a transcript entry.
///
/// Streaming text is never persisted by the chat controller; the state exists
/// so restored history can be honest about partial, interrupted, or failed
/// output without treating it as a successful model response.
enum AiMessageDelivery { complete, streaming, failed, interrupted }

/// One immutable transcript entry.
///
/// Content is supplied by the caller: the domain model never invents assistant
/// output. [isInterrupted] remains the compatibility view for real partial
/// model output that was cancelled or cut short.
class AiMessage {
  const AiMessage({
    required this.role,
    required this.content,
    required this.timestamp,
    this.id,
    this.conversationId,
    this.toolCallId,
    this.metadata = const <String, String>{},
    AiMessageDelivery delivery = AiMessageDelivery.complete,
    bool isInterrupted = false,
  })  : _wasInterrupted = isInterrupted,
        delivery = isInterrupted ? AiMessageDelivery.interrupted : delivery;

  final String? id;
  final String? conversationId;
  final AiMessageRole role;
  final String content;
  final DateTime timestamp;
  final String? toolCallId;
  final Map<String, String> metadata;
  final AiMessageDelivery delivery;
  final bool _wasInterrupted;

  bool get isInterrupted =>
      _wasInterrupted || delivery == AiMessageDelivery.interrupted;

  /// Metadata from this model is presentation-only and must never contain
  /// credentials. The storage layer applies an additional key filter.
  Map<String, String> get safeMetadata => Map<String, String>.unmodifiable(
        metadata,
      );

  AiMessage copyWith({
    String? id,
    String? conversationId,
    AiMessageRole? role,
    String? content,
    DateTime? timestamp,
    String? toolCallId,
    Map<String, String>? metadata,
    AiMessageDelivery? delivery,
  }) {
    return AiMessage(
      id: id ?? this.id,
      conversationId: conversationId ?? this.conversationId,
      role: role ?? this.role,
      content: content ?? this.content,
      timestamp: timestamp ?? this.timestamp,
      toolCallId: toolCallId ?? this.toolCallId,
      metadata: metadata ?? this.metadata,
      delivery: delivery ?? this.delivery,
      isInterrupted: isInterrupted,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        if (id != null && id!.isNotEmpty) 'id': id,
        if (conversationId != null && conversationId!.isNotEmpty)
          'conversationId': conversationId,
        'role': role.name,
        'content': content,
        'timestamp': timestamp.toIso8601String(),
        if (toolCallId != null) 'toolCallId': toolCallId,
        'delivery': delivery.name,
        // Kept for readers of the previous schema.
        if (isInterrupted) 'interrupted': true,
        if (metadata.isNotEmpty) 'metadata': safeMetadata,
      };

  factory AiMessage.fromJson(Map<String, dynamic> json) {
    final AiMessageRole role = AiMessageRole.values.firstWhere(
      (AiMessageRole item) => item.name == json['role'],
      orElse: () => AiMessageRole.user,
    );
    final AiMessageDelivery delivery = json['delivery'] is String
        ? AiMessageDelivery.values.firstWhere(
            (AiMessageDelivery item) => item.name == json['delivery'],
            orElse: () => json['interrupted'] == true
                ? AiMessageDelivery.interrupted
                : AiMessageDelivery.complete,
          )
        : json['interrupted'] == true
            ? AiMessageDelivery.interrupted
            : AiMessageDelivery.complete;

    final Map<String, String> metadata = <String, String>{};
    if (json['metadata'] is Map<String, dynamic>) {
      (json['metadata'] as Map<String, dynamic>).forEach(
        (String key, Object? value) {
          if (value != null) metadata[key] = value.toString();
        },
      );
    }
    final String? id = json['id'] as String?;
    final String? conversationId = json['conversationId'] as String?;
    return AiMessage(
      id: id == null || id.isEmpty ? null : id,
      conversationId: conversationId == null || conversationId.isEmpty
          ? null
          : conversationId,
      role: role,
      content: (json['content'] as String?) ?? '',
      timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      toolCallId: json['toolCallId'] as String?,
      metadata: metadata,
      delivery: delivery,
    );
  }
}

/// Derives a local, deterministic title from the first user message.
///
/// No model request is made just to name a conversation.
String aiConversationTitleFromContent(String content) {
  final String normalised = content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (normalised.isEmpty) return 'New conversation';
  final String title = normalised.split(' ').take(6).join(' ').trim();
  return title.isEmpty ? 'New conversation' : title;
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
    this.profileScope = 'family',
    this.archived = false,
    this.pinned = false,
  }) : _messages = messages;

  final String id;
  final List<AiMessage> _messages;
  final String? title;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String profileScope;
  final bool archived;
  final bool pinned;

  /// Returns an unmodifiable view of the transcript, oldest first.
  List<AiMessage> list() => List<AiMessage>.unmodifiable(_messages);

  int get length => _messages.length;
  int get messageCount => _messages.length;
  bool get isEmpty => _messages.isEmpty;
  bool get isNotEmpty => _messages.isNotEmpty;

  /// A compact, single-line preview for history tiles and search results.
  String get preview {
    for (int index = _messages.length - 1; index >= 0; index--) {
      final String text = _messages[index]
          .content
          .replaceAll(
            RegExp(r'\s+'),
            ' ',
          )
          .trim();
      if (text.isEmpty) continue;
      return text.length <= 120 ? text : '${text.substring(0, 120)}…';
    }
    return 'No messages yet';
  }

  /// A stable display title, derived from the first user message when needed.
  String get displayTitle {
    final String? explicit = title?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    for (final AiMessage message in _messages) {
      if (message.role == AiMessageRole.user) {
        final String derived = aiConversationTitleFromContent(message.content);
        if (derived != 'New conversation') return derived;
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
    String? profileScope,
    bool? archived,
    bool? pinned,
    bool clearTitle = false,
  }) {
    return AiConversation(
      id: id ?? this.id,
      messages: messages ?? _messages,
      title: clearTitle ? null : title ?? this.title,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      profileScope: profileScope ?? this.profileScope,
      archived: archived ?? this.archived,
      pinned: pinned ?? this.pinned,
    );
  }

  /// Appends a caller-supplied message in timestamp order, dropping the oldest
  /// entries when the configured bound is exceeded.
  AiConversation append(AiMessage message) {
    if (message.id != null &&
        _messages.any((AiMessage item) => item.id == message.id)) {
      return this;
    }

    final List<AiMessage> combined = List<AiMessage>.from(_messages);
    int insertAt = combined.length;
    while (insertAt > 0 &&
        combined[insertAt - 1].timestamp.isAfter(message.timestamp)) {
      insertAt--;
    }
    combined.insert(insertAt, message);

    final int limit = AuraRuntimeConfig.maxConversationMessages;
    final List<AiMessage> kept = combined.length > limit
        ? combined.sublist(combined.length - limit)
        : combined;

    final bool hasExplicitTitle = title != null && title!.trim().isNotEmpty;
    final String? nextTitle = hasExplicitTitle
        ? title
        : message.role == AiMessageRole.user
            ? aiConversationTitleFromContent(message.content)
            : title;
    final DateTime? firstTimestamp = <DateTime?>[
      createdAt,
      if (kept.isNotEmpty) kept.first.timestamp,
    ].reduce(
      (DateTime? a, DateTime? b) {
        if (a == null) return b;
        if (b == null) return a;
        return a.isBefore(b) ? a : b;
      },
    );
    final DateTime? lastTimestamp = <DateTime?>[
      updatedAt,
      message.timestamp,
    ].reduce(
      (DateTime? a, DateTime? b) {
        if (a == null) return b;
        if (b == null) return a;
        return a.isAfter(b) ? a : b;
      },
    );

    return copyWith(
      messages: List<AiMessage>.unmodifiable(kept),
      title: nextTitle,
      createdAt: firstTimestamp,
      updatedAt: lastTimestamp,
    );
  }

  /// Returns a fresh empty conversation with the same id and metadata.
  AiConversation clear({DateTime? now}) => AiConversation(
        id: id,
        title: title,
        createdAt: createdAt,
        updatedAt: now ?? DateTime.now(),
        profileScope: profileScope,
        archived: archived,
        pinned: pinned,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'profileScope': profileScope,
        if (title != null) 'title': title,
        'createdAt': createdAt?.toIso8601String(),
        'updatedAt': updatedAt?.toIso8601String(),
        'archived': archived,
        'pinned': pinned,
        'messageCount': messageCount,
        'preview': preview,
        'messages': _messages
            .map((AiMessage message) => message.toJson())
            .toList(growable: false),
      };

  factory AiConversation.fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Conversation id is missing.');
    }
    final Object? rawScope =
        json['profileScope'] ?? json['scope'] ?? json['profile'];
    final String profileScope =
        rawScope is String && rawScope.isNotEmpty ? rawScope : 'family';
    if (profileScope != 'family' && profileScope != 'ayush') {
      throw FormatException(
          'Unknown conversation profile scope: $profileScope');
    }

    final List<AiMessage> messages = <AiMessage>[];
    final Set<String> seenMessageIds = <String>{};
    final Object? rawMessages = json['messages'];
    if (rawMessages is List<dynamic>) {
      for (final Object? item in rawMessages) {
        if (item is! Map<String, dynamic>) continue;
        final AiMessage message = AiMessage.fromJson(item);
        if (message.id != null) {
          if (!seenMessageIds.add(message.id!)) continue;
        }
        final AiMessage scoped = message.conversationId == null
            ? message.copyWith(conversationId: id)
            : message;
        if (scoped.conversationId != id) continue;
        messages.add(scoped);
      }
    }
    messages
        .sort((AiMessage a, AiMessage b) => a.timestamp.compareTo(b.timestamp));
    if (messages.length > AuraRuntimeConfig.maxConversationMessages) {
      messages.removeRange(
        0,
        messages.length - AuraRuntimeConfig.maxConversationMessages,
      );
    }

    return AiConversation(
      id: id,
      profileScope: profileScope,
      title: json['title'] as String?,
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? ''),
      updatedAt: DateTime.tryParse((json['updatedAt'] as String?) ?? ''),
      archived: json['archived'] == true,
      pinned: json['pinned'] == true,
      messages: List<AiMessage>.unmodifiable(messages),
    );
  }
}
