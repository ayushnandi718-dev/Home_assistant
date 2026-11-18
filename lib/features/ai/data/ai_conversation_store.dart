import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Persists bounded AI conversation history in a profile-isolated JSON file.
///
/// AYUSH and FAMILY use different filenames, so their ids, titles and message
/// content can never be mixed by this store.
class AiConversationStore {
  AiConversationStore({
    Directory? directory,
    required AuraProfile profile,
  }) : _file = File(
          '${(directory ?? LocalPaths.appData()).path}${Platform.pathSeparator}ai_conversations_${profile.storageScope}.json',
        );

  final File _file;

  Future<List<AiConversation>> load() async {
    try {
      if (!await _file.exists()) return const <AiConversation>[];
      final Object? decoded = jsonDecode(await _file.readAsString());
      if (decoded is! List<dynamic>) return const <AiConversation>[];
      final List<AiConversation> result = <AiConversation>[];
      final Set<String> seenIds = <String>{};
      for (final Object? item in decoded) {
        if (item is! Map<String, dynamic>) continue;
        try {
          final AiConversation conversation = AiConversation.fromJson(item);
          if (seenIds.add(conversation.id)) result.add(conversation);
        } on FormatException {
          // Skip one malformed record without discarding valid history.
          continue;
        }
      }
      result.sort((AiConversation a, AiConversation b) =>
          b.sortTime.compareTo(a.sortTime));
      return result.take(AuraRuntimeConfig.maxAiConversations).toList();
    } catch (_) {
      return const <AiConversation>[];
    }
  }

  Future<void> save(List<AiConversation> conversations) async {
    try {
      await _file.parent.create(recursive: true);
      final List<AiConversation> bounded =
          List<AiConversation>.from(conversations)
            ..sort((AiConversation a, AiConversation b) =>
                b.sortTime.compareTo(a.sortTime));
      await _file.writeAsString(
        jsonEncode(
          bounded
              .take(AuraRuntimeConfig.maxAiConversations)
              .map((AiConversation item) => item.toJson())
              .toList(),
        ),
        flush: true,
      );
    } catch (_) {
      // A failed write must never break chat; the next mutation retries it.
    }
  }
}
