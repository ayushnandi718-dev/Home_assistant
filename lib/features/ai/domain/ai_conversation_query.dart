import 'package:aura_hub/features/ai/domain/ai_conversation.dart';

/// Date buckets used by the compact conversation history rail.
enum AiConversationDateGroup {
  today,
  yesterday,
  previous7Days,
  older,
}

extension AiConversationDateGroupX on AiConversationDateGroup {
  String get label {
    switch (this) {
      case AiConversationDateGroup.today:
        return 'Today';
      case AiConversationDateGroup.yesterday:
        return 'Yesterday';
      case AiConversationDateGroup.previous7Days:
        return 'Previous 7 days';
      case AiConversationDateGroup.older:
        return 'Older';
    }
  }
}

class AiConversationGroup {
  const AiConversationGroup({
    required this.group,
    required this.conversations,
  });

  final AiConversationDateGroup group;
  final List<AiConversation> conversations;

  String get label => group.label;
}

DateTime _startOfDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// Filters an already profile-scoped list by title, preview, or message text.
///
/// The caller is responsible for supplying only the active profile's history;
/// this helper never reaches into storage and cannot cross a profile boundary.
List<AiConversation> searchAiConversations(
  List<AiConversation> conversations, {
  String query = '',
}) {
  final String needle = query.trim().toLowerCase();
  final List<AiConversation> sorted = List<AiConversation>.from(conversations)
    ..sort((AiConversation a, AiConversation b) =>
        b.sortTime.compareTo(a.sortTime));
  if (needle.isEmpty) return sorted;

  return sorted.where((AiConversation conversation) {
    if (conversation.displayTitle.toLowerCase().contains(needle)) return true;
    if (conversation.preview.toLowerCase().contains(needle)) return true;
    for (final AiMessage message in conversation.list()) {
      if (message.content.toLowerCase().contains(needle)) return true;
    }
    return false;
  }).toList(growable: false);
}

/// Groups an already sorted profile-scoped list into stable date buckets.
List<AiConversationGroup> groupAiConversationsByDate(
  List<AiConversation> conversations, {
  DateTime? now,
}) {
  final DateTime today = _startOfDay(now ?? DateTime.now());
  final DateTime yesterday = today.subtract(const Duration(days: 1));
  final DateTime weekStart = today.subtract(const Duration(days: 7));

  final Map<AiConversationDateGroup, List<AiConversation>> buckets =
      <AiConversationDateGroup, List<AiConversation>>{
    for (final AiConversationDateGroup group in AiConversationDateGroup.values)
      group: <AiConversation>[],
  };

  for (final AiConversation conversation in conversations) {
    final DateTime day = _startOfDay(conversation.sortTime);
    if (day == today) {
      buckets[AiConversationDateGroup.today]!.add(conversation);
    } else if (day == yesterday) {
      buckets[AiConversationDateGroup.yesterday]!.add(conversation);
    } else if (day.isAfter(weekStart) && day.isBefore(yesterday)) {
      buckets[AiConversationDateGroup.previous7Days]!.add(conversation);
    } else {
      buckets[AiConversationDateGroup.older]!.add(conversation);
    }
  }

  return <AiConversationGroup>[
    for (final AiConversationDateGroup group in AiConversationDateGroup.values)
      if (buckets[group]!.isNotEmpty)
        AiConversationGroup(
          group: group,
          conversations: List<AiConversation>.unmodifiable(buckets[group]!),
        ),
  ];
}
