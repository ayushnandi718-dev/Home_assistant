import 'dart:async';

import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_query.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Compact, profile-aware conversation history list.
///
/// The panel receives only the active profile's already-filtered history. It
/// never reads another profile's repository and owns only transient search UI
/// state, which the parent keys by profile/session so it cannot leak.
class ConversationHistoryPanel extends StatefulWidget {
  const ConversationHistoryPanel({
    required this.profile,
    required this.conversations,
    required this.activeId,
    required this.recovery,
    required this.now,
    required this.onNew,
    required this.onOpen,
    required this.onRename,
    required this.onDelete,
    required this.onRetry,
    super.key,
  });

  final AuraProfile profile;
  final List<AiConversation> conversations;
  final String? activeId;
  final ValueListenable<AiConversationRecoveryState> recovery;
  final DateTime Function() now;
  final Future<void> Function() onNew;
  final Future<void> Function(String id) onOpen;
  final Future<void> Function(AiConversation conversation) onRename;
  final Future<void> Function(AiConversation conversation) onDelete;
  final Future<void> Function() onRetry;

  @override
  State<ConversationHistoryPanel> createState() =>
      _ConversationHistoryPanelState();
}

class _ConversationHistoryPanelState extends State<ConversationHistoryPanel> {
  final TextEditingController _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted) return;
      setState(() => _query = value.trim());
    });
  }

  void _clearSearch() {
    _debounce?.cancel();
    _search.clear();
    if (_query.isNotEmpty) setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool privateProfile = widget.profile == AuraProfile.ayush;

    return GlassContainer(
      surface: AuraGlassSurface.panel,
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.forum_outlined, size: 18, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text('Conversations', style: text.titleSmall),
              ),
              Tooltip(
                message: 'New conversation',
                child: IconButton(
                  icon: const Icon(Icons.add_outlined, size: 18),
                  onPressed: widget.onNew,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.xs),
          TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search titles and messages',
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 16),
                      tooltip: 'Clear search',
                      onPressed: _clearSearch,
                    ),
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AuraSpace.sm,
                vertical: AuraSpace.sm,
              ),
            ),
          ),
          if (privateProfile) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            const _PrivateStorageNotice(),
          ],
          const SizedBox(height: AuraSpace.sm),
          Expanded(
            child: ValueListenableBuilder<AiConversationRecoveryState>(
              valueListenable: widget.recovery,
              builder: (
                BuildContext context,
                AiConversationRecoveryState recovery,
                Widget? _,
              ) {
                if (recovery.phase == AiConversationLoadPhase.loading) {
                  return const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        value: 0.45,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }
                if (recovery.phase == AiConversationLoadPhase.failed) {
                  return _HistoryError(
                    message: recovery.message ??
                        'Conversation history could not be loaded.',
                    onRetry: widget.onRetry,
                  );
                }

                final List<AiConversation> visible = searchAiConversations(
                  widget.conversations,
                  query: _query,
                );
                if (visible.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AuraSpace.md),
                      child: Text(
                        _query.isEmpty
                            ? 'No saved conversations yet.'
                            : 'No conversations match this search.',
                        style: text.bodySmall,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final List<AiConversationGroup> groups =
                    groupAiConversationsByDate(visible, now: widget.now());
                return ListView.builder(
                  itemCount: groups.length,
                  itemBuilder: (BuildContext context, int groupIndex) {
                    final AiConversationGroup group = groups[groupIndex];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AuraSpace.xs,
                            AuraSpace.sm,
                            AuraSpace.xs,
                            AuraSpace.xs,
                          ),
                          child: Text(
                            group.label.toUpperCase(),
                            style: text.labelSmall?.copyWith(
                              color: AuraColors.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        for (final AiConversation conversation
                            in group.conversations)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AuraSpace.xs),
                            child: _ConversationTile(
                              conversation: conversation,
                              active: conversation.id == widget.activeId,
                              now: widget.now(),
                              onTap: () => widget.onOpen(conversation.id),
                              onRename: () => widget.onRename(conversation),
                              onDelete: () => widget.onDelete(conversation),
                            ),
                          ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            privateProfile
                ? 'Encrypted locally in this workspace only.'
                : 'Stored locally in this workspace only.',
            style: text.labelSmall?.copyWith(color: AuraColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PrivateStorageNotice extends StatelessWidget {
  const _PrivateStorageNotice();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(AuraSpace.sm),
      decoration: BoxDecoration(
        color: AuraColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AuraRadius.control),
        border: Border.all(
          color: AuraColors.primary.withValues(alpha: 0.22),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Icon(Icons.lock_outline, size: 14, color: AuraColors.primary),
          const SizedBox(width: AuraSpace.xs),
          Expanded(
            child: Text(
              'Private history is encrypted on this device. Unlocking AYUSH with your PIN is required to view it.',
              style: text.labelSmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryError extends StatelessWidget {
  const _HistoryError({required this.message, required this.onRetry});

  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.error_outline, color: AuraColors.danger, size: 22),
          const SizedBox(height: AuraSpace.xs),
          Text(
            message,
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
          TextButton(
            onPressed: onRetry,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.active,
    required this.now,
    required this.onTap,
    required this.onRename,
    required this.onDelete,
  });

  final AiConversation conversation;
  final bool active;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final String preview = conversation.preview;
    return Material(
      color: Colors.transparent,
      child: ListTile(
        dense: true,
        onTap: onTap,
        selected: active,
        selectedTileColor: AuraColors.primary.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AuraRadius.control),
          side: BorderSide(
            color: active
                ? AuraColors.primary.withValues(alpha: 0.32)
                : Colors.transparent,
          ),
        ),
        title: Row(
          children: <Widget>[
            if (conversation.pinned)
              const Padding(
                padding: EdgeInsets.only(right: AuraSpace.xxs),
                child: Icon(Icons.push_pin, size: 12),
              ),
            Expanded(
              child: Text(
                conversation.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        subtitle: Text(
          '$preview · ${formatRelativeTime(conversation.sortTime, now: now)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: PopupMenuButton<String>(
          tooltip: 'Conversation actions',
          onSelected: (String value) {
            if (value == 'rename') onRename();
            if (value == 'delete') onDelete();
          },
          itemBuilder: (BuildContext context) => const <PopupMenuEntry<String>>[
            PopupMenuItem<String>(value: 'rename', child: Text('Rename')),
            PopupMenuItem<String>(value: 'delete', child: Text('Delete')),
          ],
        ),
      ),
    );
  }
}
