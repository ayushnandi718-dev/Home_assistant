import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_input_policy.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/presentation/ai_markdown_view.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/ai/presentation/conversation_history_panel.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/glass/glass_badge.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

const List<String> _examplePrompts = <String>[
  'Explain a technical concept in simple terms.',
  'Help me debug this code step by step.',
  'Summarise a topic into five useful points.',
  'Help me plan my day around focused work.',
];

/// AURA Assistant chat workspace.
///
/// Nothing is generated locally and no response is simulated. Messages leave
/// the device only after explicit, persisted per-profile consent.
class AiPage extends ConsumerStatefulWidget {
  const AiPage({super.key});

  @override
  ConsumerState<AiPage> createState() => _AiPageState();
}

class _AiPageState extends ConsumerState<AiPage> {
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final ScrollController _messageScroll = ScrollController();
  bool _showSettings = false;

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    _messageScroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_messageScroll.hasClients) return;
      _messageScroll.animateTo(
        _messageScroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
      );
    });
  }

  AiProviderConfig? _selectedConfig(
    List<AiProviderConfig> configs,
    AiPreferences preferences,
  ) {
    final String? id = preferences.selectedProviderId;
    if (id != null) {
      for (final AiProviderConfig config in configs) {
        if (config.id == id) return config;
      }
    }
    for (final AiProviderConfig config in configs) {
      if (config.enabled) return config;
    }
    return configs.isEmpty ? null : configs.first;
  }

  Future<bool> _ensureConsent(AiProviderConfig? config) async {
    final AiPreferences preferences = ref.read(activeAiPreferencesProvider);
    if (preferences.consentGranted) return true;

    final bool memoryRetrievalEnabled =
        ref.read(activeMemorySettingsProvider).retrievalEnabled;
    final bool? accepted = await showGlassDialog<bool>(
      context: context,
      width: 620,
      child: _ConsentDialog(
        config: config,
        memoryRetrievalEnabled: memoryRetrievalEnabled,
      ),
    );
    if (accepted != true || !mounted) return false;
    await ref.read(activeAiPreferencesControllerProvider).setConsent(true);
    return true;
  }

  Future<void> _send() async {
    final String text = _composer.text.trim();
    if (text.isEmpty || ref.read(activeAiChatStateProvider).isBusy) return;

    if (AiInputPolicy.isBlocked(text)) {
      // Keep the text so the user can rephrase instead of retyping it.
      ref.read(activeAiChatControllerProvider).showBlockedInput();
      return;
    }

    final AiPreferences preferences = ref.read(activeAiPreferencesProvider);
    final AiProviderConfig? config =
        _selectedConfig(ref.read(activeAiConfigsProvider), preferences);

    if (!await _ensureConsent(config)) return;
    if (!mounted) return;

    _composer.clear();
    await ref.read(activeAiChatControllerProvider).send(text);
    if (mounted) _scrollToBottom();
  }

  void _usePrompt(String prompt) {
    _composer.text = prompt;
    _composerFocus.requestFocus();
  }

  Future<void> _newConversation() async {
    final String id =
        ref.read(activeAiConversationsControllerProvider).create();
    await ref
        .read(activeAiPreferencesControllerProvider)
        .setActiveConversation(id);
    _composer.clear();
  }

  Future<void> _selectConversation(String id) async {
    await ref
        .read(activeAiPreferencesControllerProvider)
        .setActiveConversation(id);
    _scrollToBottom();
  }

  Future<void> _showHistory(
    AuraProfile profile,
    List<AiConversation> conversations,
    ValueKey<String> historyKey,
    ValueListenable<AiConversationRecoveryState> recovery,
  ) async {
    final Widget panel = ConversationHistoryPanel(
      key: historyKey,
      profile: profile,
      conversations: conversations,
      activeId: ref.read(activeAiPreferencesProvider).activeConversationId,
      recovery: recovery,
      now: DateTime.now,
      onNew: _newConversation,
      onOpen: _selectConversation,
      onRename: _renameConversation,
      onDelete: _deleteConversation,
      onRetry: () => ref.read(activeAiConversationsControllerProvider).load(),
    );

    if (MediaQuery.sizeOf(context).width < AuraBreakpoints.mobile) {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (BuildContext context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AuraSpace.md),
            child: SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.72,
              child: panel,
            ),
          ),
        ),
      );
      return;
    }
    await showGlassDialog<void>(
      context: context,
      width: 420,
      child: SizedBox(height: 420, child: panel),
    );
  }

  Future<void> _renameConversation(AiConversation conversation) async {
    final TextEditingController controller =
        TextEditingController(text: conversation.title ?? '');
    final String? next = await showGlassDialog<String>(
      context: context,
      width: 480,
      child: _RenameDialog(controller: controller),
    );
    controller.dispose();
    if (next == null || !mounted) return;
    await ref
        .read(activeAiConversationsControllerProvider)
        .rename(conversation.id, next);
  }

  Future<void> _deleteConversation(AiConversation conversation) async {
    final bool? confirmed = await showGlassDialog<bool>(
      context: context,
      width: 460,
      child: _ConfirmDeleteDialog(title: conversation.displayTitle),
    );
    if (confirmed != true || !mounted) return;
    final AiConversationLibraryController library =
        ref.read(activeAiConversationsControllerProvider);
    final AiPreferences preferences = ref.read(activeAiPreferencesProvider);
    await library.delete(conversation.id);
    if (preferences.activeConversationId == conversation.id) {
      await ref
          .read(activeAiPreferencesControllerProvider)
          .setActiveConversation(null);
    }
  }

  Future<void> _clearConversation() async {
    final String? id =
        ref.read(activeAiPreferencesProvider).activeConversationId;
    if (id == null) return;
    final bool? confirmed = await showGlassDialog<bool>(
      context: context,
      width: 460,
      child: const _ConfirmClearDialog(),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(activeAiConversationsControllerProvider).clear(id);
  }

  Future<void> _copy(String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Response copied to clipboard')),
    );
  }

  /// Creates a pending memory only after the user confirms editable content.
  ///
  /// Nothing is extracted in the background: the selected chat text, or the
  /// whole message when nothing is selected, is a starting point for review.
  Future<void> _remember(AiMessage message, String content) async {
    final String initial = content.trim();
    if (initial.isEmpty) return;

    final _MemorySuggestionDraft? draft =
        await showGlassDialog<_MemorySuggestionDraft>(
      context: context,
      width: 560,
      child: _MemorySuggestionDialog(initialText: initial),
    );
    if (draft == null || !mounted) return;

    final String? conversationId =
        ref.read(activeAiPreferencesProvider).activeConversationId;
    final bool saved = await ref.read(activeMemoryControllerProvider).suggest(
          content: draft.content,
          category: draft.category,
          sourceConversationId: conversationId,
          sourceMessageId:
              '${message.timestamp.microsecondsSinceEpoch}-${message.role.name}',
        );
    if (!mounted) return;

    final String? error = ref.read(activeMemoryStateProvider).errorMessage;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          saved
              ? 'Saved as a pending memory. Review it in AURA Memory.'
              : error ?? 'That memory could not be saved.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Riverpod only allows ref.listen during build. Keeping the listener here
    // also ties it to the current provider scope when profiles switch.
    ref.listen<AiChatState>(activeAiChatStateProvider, (previous, next) {
      if (next.streamingText != previous?.streamingText) {
        _scrollToBottom();
      }
    });

    final AuraProfile profile = ref.watch(activeProfileProvider);
    final ProfileSession session = ref.watch(profileSessionProvider);
    final AiConversationLibraryController conversationLibrary =
        ref.watch(activeAiConversationsControllerProvider);
    final List<AiConversation> conversations =
        ref.watch(activeAiConversationsProvider);
    final ValueKey<String> historyKey = ValueKey<String>(
      '${profile.storageScope}-${session.startedAt.microsecondsSinceEpoch}',
    );
    final AiPreferences preferences = ref.watch(activeAiPreferencesProvider);
    final List<AiProviderConfig> configs = ref.watch(activeAiConfigsProvider);
    final AiProviderConfig? config = _selectedConfig(configs, preferences);
    final AiReadiness readiness = ref.watch(aiReadinessProvider);
    final AiChatStatus chatStatus = ref.watch(activeAiChatStatusProvider);
    final AiChatState chat = ref.watch(activeAiChatStateProvider);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.lg,
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PageHeader(
            eyebrow: 'Experience / Intelligence',
            title: 'AURA Assistant',
            description:
                'Streaming, multilingual help with explicit consent and local chat history.',
            icon: Icons.auto_awesome_outlined,
            accent: AuraColors.secondary,
            trailing: Wrap(
              spacing: AuraSpace.sm,
              runSpacing: AuraSpace.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                StatusPill(
                  label: readiness.label,
                  color: _readinessColor(readiness),
                  dense: true,
                ),
                StatusPill(
                  label: chatStatus.label,
                  color: _chatStatusColor(chatStatus),
                  dense: true,
                ),
                OutlinedButton.icon(
                  onPressed: () =>
                      setState(() => _showSettings = !_showSettings),
                  icon: Icon(
                    _showSettings ? Icons.chat_outlined : Icons.tune_outlined,
                    size: 16,
                  ),
                  label: Text(_showSettings ? 'Back to chat' : 'Provider'),
                ),
                FilledButton.icon(
                  onPressed: _newConversation,
                  icon: const Icon(Icons.add_outlined, size: 16),
                  label: const Text('New chat'),
                ),
              ],
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          if (!preferences.consentGranted)
            InfoBanner(
              title: 'External AI requests are off',
              message:
                  'Conversations stay local until you approve sending a message to '
                  '${config?.label ?? 'the configured provider'}. You can revoke consent anytime in Provider settings.',
              icon: Icons.privacy_tip_outlined,
              tone: AuraBannerTone.privacy,
              trailing: TextButton(
                onPressed: () => _ensureConsent(config),
                child: const Text('Review'),
              ),
            ),
          const SizedBox(height: AuraSpace.md),
          Expanded(
            child: _showSettings
                ? const _ProviderSettingsPanel()
                : _Workspace(
                    profile: profile,
                    historyKey: historyKey,
                    conversations: conversations,
                    recovery: conversationLibrary.recoveryNotifier,
                    onRetryHistory: conversationLibrary.load,
                    onHistory: () => _showHistory(
                      profile,
                      conversations,
                      historyKey,
                      conversationLibrary.recoveryNotifier,
                    ),
                    preferences: preferences,
                    configs: configs,
                    config: config,
                    chat: chat,
                    composer: _composer,
                    composerFocus: _composerFocus,
                    messageScroll: _messageScroll,
                    onSend: _send,
                    onCancel: () =>
                        ref.read(activeAiChatControllerProvider).cancel(),
                    onRetry: () =>
                        ref.read(activeAiChatControllerProvider).retry(),
                    onPrompt: _usePrompt,
                    onNew: _newConversation,
                    onSelect: _selectConversation,
                    onRename: _renameConversation,
                    onDelete: _deleteConversation,
                    onClear: _clearConversation,
                    onCopy: _copy,
                    onRemember: _remember,
                  ),
          ),
        ],
      ),
    );
  }
}

Color _readinessColor(AiReadiness readiness) {
  switch (readiness) {
    case AiReadiness.connected:
      return AuraColors.success;
    case AiReadiness.error:
    case AiReadiness.needsConfiguration:
    case AiReadiness.needsCredential:
    case AiReadiness.needsRefresh:
      return AuraColors.warning;
    case AiReadiness.disconnected:
      return AuraColors.textSecondary;
    case AiReadiness.unconfigured:
      return AuraColors.textSecondary;
  }
}

Color _chatStatusColor(AiChatStatus status) {
  switch (status) {
    case AiChatStatus.idle:
      return AuraColors.textSecondary;
    case AiChatStatus.running:
      return AuraColors.primary;
    case AiChatStatus.failed:
      return AuraColors.danger;
  }
}

class _Workspace extends StatelessWidget {
  const _Workspace({
    required this.profile,
    required this.historyKey,
    required this.recovery,
    required this.onRetryHistory,
    required this.onHistory,
    required this.conversations,
    required this.preferences,
    required this.configs,
    required this.config,
    required this.chat,
    required this.composer,
    required this.composerFocus,
    required this.messageScroll,
    required this.onSend,
    required this.onCancel,
    required this.onRetry,
    required this.onPrompt,
    required this.onNew,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
    required this.onClear,
    required this.onCopy,
    required this.onRemember,
  });

  final AuraProfile profile;
  final ValueKey<String> historyKey;
  final ValueListenable<AiConversationRecoveryState> recovery;
  final Future<void> Function() onRetryHistory;
  final Future<void> Function() onHistory;
  final List<AiConversation> conversations;
  final AiPreferences preferences;
  final List<AiProviderConfig> configs;
  final AiProviderConfig? config;
  final AiChatState chat;
  final TextEditingController composer;
  final FocusNode composerFocus;
  final ScrollController messageScroll;
  final Future<void> Function() onSend;
  final VoidCallback onCancel;
  final Future<void> Function() onRetry;
  final void Function(String prompt) onPrompt;
  final Future<void> Function() onNew;
  final Future<void> Function(String id) onSelect;
  final Future<void> Function(AiConversation conversation) onRename;
  final Future<void> Function(AiConversation conversation) onDelete;
  final Future<void> Function() onClear;
  final Future<void> Function(String content) onCopy;
  final Future<void> Function(AiMessage message, String content) onRemember;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 980;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (wide) ...<Widget>[
              SizedBox(
                width: 272,
                child: ConversationHistoryPanel(
                  key: historyKey,
                  profile: profile,
                  conversations: conversations,
                  activeId: preferences.activeConversationId,
                  recovery: recovery,
                  now: DateTime.now,
                  onNew: onNew,
                  onOpen: onSelect,
                  onRename: onRename,
                  onDelete: onDelete,
                  onRetry: onRetryHistory,
                ),
              ),
              const SizedBox(width: AuraSpace.md),
            ],
            Expanded(
              child: _ChatPanel(
                profile: profile,
                preferences: preferences,
                configs: configs,
                config: config,
                chat: chat,
                composer: composer,
                composerFocus: composerFocus,
                messageScroll: messageScroll,
                onSend: onSend,
                onCancel: onCancel,
                onRetry: onRetry,
                onPrompt: onPrompt,
                onNew: onNew,
                onSelect: onSelect,
                onHistory: onHistory,
                onClear: onClear,
                onCopy: onCopy,
                onRemember: onRemember,
                compact: !wide,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ChatPanel extends ConsumerWidget {
  const _ChatPanel({
    required this.profile,
    required this.preferences,
    required this.configs,
    required this.config,
    required this.chat,
    required this.composer,
    required this.composerFocus,
    required this.messageScroll,
    required this.onSend,
    required this.onCancel,
    required this.onRetry,
    required this.onPrompt,
    required this.onNew,
    required this.onSelect,
    required this.onHistory,
    required this.onClear,
    required this.onCopy,
    required this.onRemember,
    required this.compact,
  });

  final AuraProfile profile;
  final AiPreferences preferences;
  final List<AiProviderConfig> configs;
  final AiProviderConfig? config;
  final AiChatState chat;
  final TextEditingController composer;
  final FocusNode composerFocus;
  final ScrollController messageScroll;
  final Future<void> Function() onSend;
  final VoidCallback onCancel;
  final Future<void> Function() onRetry;
  final void Function(String prompt) onPrompt;
  final Future<void> Function() onNew;
  final Future<void> Function(String id) onSelect;
  final Future<void> Function() onHistory;
  final Future<void> Function() onClear;
  final Future<void> Function(String content) onCopy;
  final Future<void> Function(AiMessage message, String content) onRemember;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AiConversation> conversations =
        ref.watch(activeAiConversationsProvider);
    final AiConversation? active = conversations.isEmpty
        ? null
        : conversations.firstWhere(
            (AiConversation item) =>
                item.id == preferences.activeConversationId,
            orElse: () => conversations.first,
          );
    final List<AiMessage> messages = active?.list() ?? const <AiMessage>[];
    final TextTheme text = Theme.of(context).textTheme;
    final String modelName = config?.model ?? '';
    final String modelSuffix = modelName.isEmpty ? '' : ' · $modelName';

    return GlassContainer(
      surface: AuraGlassSurface.panel,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AuraSpace.lg,
              AuraSpace.md,
              AuraSpace.md,
              AuraSpace.md,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AuraRadius.control),
                    gradient: const LinearGradient(
                      colors: <Color>[AuraColors.primary, AuraColors.secondary],
                    ),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: AuraColors.onAccent,
                  ),
                ),
                const SizedBox(width: AuraSpace.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        active?.displayTitle ?? 'New conversation',
                        style: text.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AuraSpace.xxs),
                      Text(
                        '${profile.label} · ${config?.label ?? 'No provider'}'
                        '$modelSuffix'
                        ' · ${messages.length} messages',
                        style: text.labelSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (compact)
                  Tooltip(
                    message: 'Conversations',
                    child: IconButton(
                      icon: const Icon(Icons.forum_outlined, size: 18),
                      onPressed: onHistory,
                    ),
                  ),
                Tooltip(
                  message: 'Clear messages',
                  child: IconButton(
                    icon: const Icon(Icons.delete_sweep_outlined, size: 18),
                    onPressed: active == null ? null : onClear,
                  ),
                ),
                Tooltip(
                  message: 'New conversation',
                  child: IconButton(
                    icon: const Icon(Icons.add_comment_outlined, size: 18),
                    onPressed: onNew,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: AuraColors.border.withValues(alpha: 0.6)),
          Expanded(
            child: messages.isEmpty && chat.streamingText == null
                ? _EmptyConversation(onPrompt: onPrompt)
                : ListView.builder(
                    controller: messageScroll,
                    padding: const EdgeInsets.fromLTRB(
                      AuraSpace.lg,
                      AuraSpace.lg,
                      AuraSpace.lg,
                      AuraSpace.sm,
                    ),
                    itemCount:
                        messages.length + (chat.streamingText == null ? 0 : 1),
                    itemBuilder: (BuildContext context, int index) {
                      if (index < messages.length) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AuraSpace.md),
                          child: _MessageBubble(
                            message: messages[index],
                            onCopy: onCopy,
                            onRemember: onRemember,
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AuraSpace.md),
                        child: _StreamingBubble(text: chat.streamingText ?? ''),
                      );
                    },
                  ),
          ),
          if (chat.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AuraSpace.lg),
              child: _ErrorBanner(
                message: chat.errorMessage ?? 'The request failed.',
                canRetry: chat.failureKind?.isRetryable ?? false,
                onRetry: onRetry,
              ),
            ),
          const SizedBox(height: AuraSpace.sm),
          _Composer(
            controller: composer,
            focusNode: composerFocus,
            isBusy: chat.isBusy,
            onSend: onSend,
            onCancel: onCancel,
          ),
        ],
      ),
    );
  }
}

class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.message,
    required this.onCopy,
    required this.onRemember,
  });

  final AiMessage message;
  final Future<void> Function(String content) onCopy;
  final Future<void> Function(AiMessage message, String content) onRemember;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble> {
  String? _selectedText;

  void _handleSelectionChanged(SelectedContent? selection) {
    final String text = selection?.plainText.trim() ?? '';
    final String? next = text.isEmpty ? null : text;
    if (next == _selectedText) return;
    setState(() => _selectedText = next);
  }

  @override
  Widget build(BuildContext context) {
    final AiMessage message = widget.message;
    final bool isUser = message.role == AiMessageRole.user;
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = isUser ? AuraColors.primary : AuraColors.secondary;
    final double maxWidth = MediaQuery.sizeOf(context).width >= 980 ? 640 : 520;
    final bool canRemember = message.content.trim().isNotEmpty;

    return Row(
      mainAxisAlignment:
          isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Container(
            padding: const EdgeInsets.fromLTRB(
              AuraSpace.md,
              AuraSpace.sm,
              AuraSpace.sm,
              AuraSpace.xs,
            ),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: isUser ? 0.16 : 0.10),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AuraRadius.card),
                topRight: const Radius.circular(AuraRadius.card),
                bottomLeft:
                    Radius.circular(isUser ? AuraRadius.card : AuraSpace.xs),
                bottomRight:
                    Radius.circular(isUser ? AuraSpace.xs : AuraRadius.card),
              ),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  isUser ? 'You' : 'AURA',
                  style: text.labelSmall?.copyWith(color: accent),
                ),
                const SizedBox(height: AuraSpace.xxs),
                SelectionArea(
                  onSelectionChanged: _handleSelectionChanged,
                  child: AiMarkdownView(text: message.content),
                ),
                const SizedBox(height: AuraSpace.xxs),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      _time(message.timestamp),
                      style: text.labelSmall?.copyWith(
                        color: AuraColors.textSecondary,
                      ),
                    ),
                    if (message.isInterrupted) ...<Widget>[
                      const SizedBox(width: AuraSpace.sm),
                      Text(
                        'interrupted',
                        style: text.labelSmall?.copyWith(
                          color: AuraColors.warning,
                        ),
                      ),
                    ],
                    if (canRemember) ...<Widget>[
                      const SizedBox(width: AuraSpace.sm),
                      Tooltip(
                        message: 'Remember this message',
                        child: InkWell(
                          onTap: () => widget.onRemember(
                            message,
                            _selectedText ?? message.content,
                          ),
                          borderRadius: BorderRadius.circular(AuraSpace.xs),
                          child: Padding(
                            padding: const EdgeInsets.all(AuraSpace.xxs),
                            child: Icon(
                              Icons.bookmark_add_outlined,
                              size: 13,
                              color: AuraColors.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ],
                    if (!isUser) ...<Widget>[
                      const SizedBox(width: AuraSpace.sm),
                      InkWell(
                        onTap: () => widget.onCopy(message.content),
                        borderRadius: BorderRadius.circular(AuraSpace.xs),
                        child: Padding(
                          padding: const EdgeInsets.all(AuraSpace.xxs),
                          child: Icon(
                            Icons.copy_outlined,
                            size: 13,
                            color: AuraColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _StreamingBubble extends StatelessWidget {
  const _StreamingBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Container(
          padding: const EdgeInsets.all(AuraSpace.md),
          decoration: BoxDecoration(
            color: AuraColors.secondary.withValues(alpha: 0.09),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(AuraRadius.card),
              topRight: Radius.circular(AuraRadius.card),
              bottomRight: Radius.circular(AuraRadius.card),
              bottomLeft: Radius.circular(AuraSpace.xs),
            ),
            border: Border.all(
              color: AuraColors.secondary.withValues(alpha: 0.26),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: AuraColors.secondary,
                    ),
                  ),
                  const SizedBox(width: AuraSpace.xs),
                  Text(
                    'AURA is responding',
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                ],
              ),
              const SizedBox(height: AuraSpace.sm),
              Text(text, style: Theme.of(context).textTheme.bodyMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({required this.onPrompt});

  final void Function(String prompt) onPrompt;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AuraSpace.lg),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: <Color>[AuraColors.primary, AuraColors.secondary],
                  ),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: AuraColors.secondary.withValues(alpha: 0.24),
                      blurRadius: 32,
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: AuraColors.onAccent,
                  size: 28,
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              Text(
                'Where should we begin?',
                style: text.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AuraSpace.sm),
              Text(
                'Choose a prompt to place it in the composer, or write your own. '
                'Nothing is sent until you press Send and consent is in place.',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AuraSpace.lg),
              Wrap(
                spacing: AuraSpace.sm,
                runSpacing: AuraSpace.sm,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  for (final String prompt in _examplePrompts)
                    SizedBox(
                      width: 300,
                      child: SurfaceCard(
                        padding: const EdgeInsets.all(AuraSpace.md),
                        onTap: () => onPrompt(prompt),
                        child: Row(
                          children: <Widget>[
                            Icon(
                              Icons.lightbulb_outline_rounded,
                              size: 17,
                              color: AuraColors.primary,
                            ),
                            const SizedBox(width: AuraSpace.sm),
                            Expanded(
                              child: Text(
                                prompt,
                                style: text.bodySmall,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({
    required this.message,
    required this.canRetry,
    required this.onRetry,
  });

  final String message;
  final bool canRetry;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AuraSpace.sm),
      decoration: BoxDecoration(
        color: AuraColors.danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AuraRadius.control),
        border: Border.all(color: AuraColors.danger.withValues(alpha: 0.26)),
      ),
      child: Row(
        children: <Widget>[
          const Icon(Icons.error_outline_rounded,
              size: 18, color: AuraColors.danger),
          const SizedBox(width: AuraSpace.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          if (canRetry)
            TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.isBusy,
    required this.onSend,
    required this.onCancel,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isBusy;
  final Future<void> Function() onSend;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AuraSpace.lg,
        0,
        AuraSpace.lg,
        AuraSpace.lg,
      ),
      padding: const EdgeInsets.all(AuraSpace.sm),
      decoration: BoxDecoration(
        color: AuraGlass.tint.withValues(alpha: 0.50),
        borderRadius: BorderRadius.circular(AuraRadius.card),
        border: Border.all(color: AuraColors.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  enabled: !isBusy,
                  maxLines: 5,
                  minLines: 1,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (String value) {
                    if (value.trim().isNotEmpty) onSend();
                  },
                  decoration: const InputDecoration(
                    hintText:
                        'Ask AURA anything…  (Shift+Enter for a new line)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: AuraSpace.sm),
              if (isBusy)
                FilledButton.icon(
                  onPressed: onCancel,
                  icon: const Icon(Icons.stop_rounded, size: 16),
                  label: const Text('Stop'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AuraColors.danger.withValues(alpha: 0.75),
                  ),
                )
              else
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (BuildContext context, TextEditingValue value, _) {
                    return FilledButton.icon(
                      onPressed: value.text.trim().isEmpty ? null : onSend,
                      icon: const Icon(Icons.send_outlined, size: 16),
                      label: const Text('Send'),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: AuraSpace.xs),
          Row(
            children: <Widget>[
              Icon(Icons.auto_awesome_outlined,
                  size: 14, color: AuraColors.textSecondary),
              const SizedBox(width: AuraSpace.xs),
              Flexible(
                child: Text(
                  'Language detected automatically',
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AuraColors.textSecondary,
                      ),
                ),
              ),
              const Spacer(),
              Flexible(
                child: Text(
                  'Enter to send · Shift+Enter for newline',
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AuraColors.textSecondary,
                      ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProviderSettingsPanel extends ConsumerWidget {
  const _ProviderSettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<AiProviderConfig> configs = ref.watch(activeAiConfigsProvider);
    final AiPreferences preferences = ref.watch(activeAiPreferencesProvider);
    final String? selectedId = preferences.selectedProviderId ??
        (configs.isEmpty ? null : configs.first.id);

    return AuraScrollArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const InfoBanner(
                title: 'Keys stay in the operating system vault',
                message:
                    'Provider settings store only the endpoint, model and a reference to the credential. A connection status appears only after a real request succeeds.',
                icon: Icons.key_outlined,
                tone: AuraBannerTone.privacy,
              ),
              const SizedBox(height: AuraSpace.md),
              _ProviderSettingsForm(
                key: ValueKey<String?>(selectedId),
                configs: configs,
                selectedId: selectedId,
              ),
              const SizedBox(height: AuraSpace.md),
              const _PrivacyControlCard(),
              const SizedBox(height: AuraSpace.md),
              const _ToolExtensionCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderSettingsForm extends ConsumerStatefulWidget {
  const _ProviderSettingsForm({
    super.key,
    required this.configs,
    required this.selectedId,
  });

  final List<AiProviderConfig> configs;
  final String? selectedId;

  @override
  ConsumerState<_ProviderSettingsForm> createState() =>
      _ProviderSettingsFormState();
}

class _ProviderSettingsFormState extends ConsumerState<_ProviderSettingsForm> {
  late final TextEditingController _label;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  final TextEditingController _apiKey = TextEditingController();
  bool _obscureKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final AiProviderConfig? config = _currentConfig();
    _label = TextEditingController(text: config?.label ?? 'Groq');
    _baseUrl = TextEditingController(
      text: config?.baseUrl ?? 'https://api.groq.com/openai/v1',
    );
    _model = TextEditingController(text: config?.model ?? '');
  }

  AiProviderConfig? _currentConfig() {
    for (final AiProviderConfig config in widget.configs) {
      if (config.id == widget.selectedId) return config;
    }
    return null;
  }

  @override
  void dispose() {
    _label.dispose();
    _baseUrl.dispose();
    _model.dispose();
    _apiKey.dispose();
    super.dispose();
  }

  void _useGroqPreset() {
    _label.text = 'Groq';
    // Base URL is public configuration; the model is intentionally left blank
    // because available model ids change and must be chosen by the user.
    _baseUrl.text = 'https://api.groq.com/openai/v1';
    setState(() {});
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final AiProviderConfig? existing = _currentConfig();
    final String providerId =
        existing?.id ?? 'provider-${DateTime.now().microsecondsSinceEpoch}';
    final AiProviderConfig config = AiProviderConfig(
      id: providerId,
      label: _label.text.trim(),
      kind: AiProviderKind.openAiCompatible,
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      enabled: true,
      language: ref.read(activeAiPreferencesProvider).language,
    );
    final String? error = config.validate();
    if (error != null) {
      setState(() => _saving = false);
      _toast(error);
      return;
    }

    await ref.read(activeAiConfigsControllerProvider).upsert(config);
    await ref
        .read(activeAiPreferencesControllerProvider)
        .selectProvider(config.id);
    ref.read(activeAiConnectionControllerProvider).invalidate();

    final String key = _apiKey.text.trim();
    if (key.isNotEmpty) {
      await ref.read(activeAiCredentialControllerProvider).save(
            providerId: config.id,
            apiKey: key,
          );
      _apiKey.clear();
    } else {
      await ref
          .read(activeAiCredentialControllerProvider)
          .refresh(providerId: config.id);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _toast('Provider saved locally. Test the connection to verify it.');
  }

  Future<void> _test() async {
    final AiProviderConfig? config = _currentConfig();
    final String? error = config?.validate();
    if (config == null || error != null) {
      _toast('Save a valid provider configuration first.');
      return;
    }
    await ref
        .read(activeAiConnectionControllerProvider)
        .test(providerId: config.id);
  }

  Future<void> _removeKey() async {
    final AiProviderConfig? config = _currentConfig();
    if (config == null) return;
    await ref
        .read(activeAiCredentialControllerProvider)
        .delete(providerId: config.id);
    ref.read(activeAiConnectionControllerProvider).markDisconnected();
    if (!mounted) return;
    _toast('Stored API key removed from the OS vault.');
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final AiCredentialState credentials =
        ref.watch(activeAiCredentialStateProvider);
    final AiConnectionState connection =
        ref.watch(activeAiConnectionStateProvider);
    final bool hasKey = credentials.presence == AiCredentialPresence.present;

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.hub_outlined, color: AuraColors.secondary, size: 20),
              const SizedBox(width: AuraSpace.sm),
              Text('Provider configuration', style: text.titleLarge),
              const Spacer(),
              GlassStatusBadge(
                label: _connectionLabel(connection.status),
                color: _connectionColor(connection.status),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          Row(
            children: <Widget>[
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: widget.selectedId,
                  decoration: const InputDecoration(
                    labelText: 'Configured provider',
                    border: OutlineInputBorder(),
                  ),
                  items: <DropdownMenuItem<String?>>[
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('New provider'),
                    ),
                    for (final AiProviderConfig config in widget.configs)
                      DropdownMenuItem<String?>(
                        value: config.id,
                        child: Text(config.label),
                      ),
                  ],
                  onChanged: (String? value) {
                    ref
                        .read(activeAiPreferencesControllerProvider)
                        .selectProvider(value);
                    ref.read(activeAiConnectionControllerProvider).invalidate();
                    if (value != null) {
                      ref
                          .read(activeAiCredentialControllerProvider)
                          .refresh(providerId: value);
                    }
                  },
                ),
              ),
              const SizedBox(width: AuraSpace.sm),
              OutlinedButton.icon(
                onPressed: _useGroqPreset,
                icon: const Icon(Icons.bolt_outlined, size: 16),
                label: const Text('Use Groq endpoint'),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          TextField(
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Display name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          TextField(
            controller: _baseUrl,
            decoration: const InputDecoration(
              labelText: 'OpenAI-compatible base URL',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
              labelText: 'Model identifier',
              hintText:
                  'Enter a currently available model id from your provider',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          TextField(
            controller: _apiKey,
            obscureText: _obscureKey,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: hasKey ? 'Replace API key' : 'API key',
              hintText: hasKey ? 'Leave blank to keep the stored key' : 'sk-…',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureKey
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _obscureKey = !_obscureKey),
              ),
            ),
          ),
          const SizedBox(height: AuraSpace.xs),
          Row(
            children: <Widget>[
              Icon(
                hasKey
                    ? Icons.verified_user_outlined
                    : Icons.no_encryption_outlined,
                size: 15,
                color: hasKey ? AuraColors.success : AuraColors.textSecondary,
              ),
              const SizedBox(width: AuraSpace.xs),
              Expanded(
                child: Text(
                  hasKey
                      ? 'A key is stored in the OS credential vault. It is never shown again.'
                      : 'No key stored for this provider in this workspace.',
                  style: text.labelSmall,
                ),
              ),
              if (hasKey)
                TextButton(
                  onPressed: _removeKey,
                  child: const Text('Remove key'),
                ),
            ],
          ),
          if (connection.message != null) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            Text(connection.message!, style: text.bodySmall),
          ],
          const SizedBox(height: AuraSpace.sm),
          Text(
            _statusSummary(connection, hasKey),
            style: text.labelSmall?.copyWith(color: AuraColors.textSecondary),
          ),
          const SizedBox(height: AuraSpace.md),
          Wrap(
            spacing: AuraSpace.sm,
            runSpacing: AuraSpace.sm,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Saving…' : 'Save provider'),
              ),
              OutlinedButton.icon(
                onPressed: connection.status == AiConnectionStatus.testing
                    ? null
                    : _test,
                icon: connection.status == AiConnectionStatus.testing
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AuraColors.primary,
                        ),
                      )
                    : const Icon(Icons.network_check_outlined, size: 16),
                label: Text(
                  connection.status == AiConnectionStatus.testing
                      ? 'Testing…'
                      : 'Test connection',
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'A successful test makes a real authenticated request to the provider. '
            'Saving a key alone never marks the provider connected.',
            style: text.labelSmall?.copyWith(color: AuraColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _PrivacyControlCard extends ConsumerWidget {
  const _PrivacyControlCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AiPreferences preferences = ref.watch(activeAiPreferencesProvider);
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.privacy_tip_outlined,
                  size: 20, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Text('External transmission consent',
                  style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            preferences.consentGranted
                ? 'Consent is active for this workspace. Messages you send will be transmitted to the configured provider.'
                : 'Consent has not been granted. No message content will be sent to any external provider.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              onPressed: preferences.consentGranted
                  ? () async {
                      await ref
                          .read(activeAiPreferencesControllerProvider)
                          .setConsent(false);
                    }
                  : null,
              icon: const Icon(Icons.lock_outline, size: 16),
              label: const Text('Revoke consent'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolExtensionCard extends StatelessWidget {
  const _ToolExtensionCard();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(Icons.extension_outlined, size: 20, color: AuraColors.primary),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Future tools',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: AuraSpace.xxs),
                Text(
                  'Tool declarations, permission levels and result messages are defined '
                  'as extension points. No tool is registered or executed in this build.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsentDialog extends StatelessWidget {
  const _ConsentDialog({
    required this.config,
    required this.memoryRetrievalEnabled,
  });

  final AiProviderConfig? config;
  final bool memoryRetrievalEnabled;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String modelName = config?.model ?? '';
    final String modelDetail = modelName.isEmpty ? '' : ' ($modelName)';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(Icons.privacy_tip_outlined,
                size: 24, color: AuraColors.secondary),
            const SizedBox(width: AuraSpace.sm),
            Text('Allow external AI?', style: text.headlineSmall),
          ],
        ),
        const SizedBox(height: AuraSpace.md),
        Text(
          'The next message will be transmitted to ${config?.label ?? 'the configured provider'}'
          '$modelDetail. Only this conversation context, the language '
          'instruction${memoryRetrievalEnabled ? ' and approved memories from this workspace' : ''} '
          'are included.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: AuraSpace.md),
        _ConsentRow(
          icon: Icons.save_outlined,
          title: 'Local storage',
          body:
              'Conversation history, language and consent stay in this workspace’s local files.',
        ),
        if (memoryRetrievalEnabled)
          _ConsentRow(
            icon: Icons.psychology_outlined,
            title: 'Approved memory',
            body:
                'Only approved memories from the active workspace may be used. '
                'AYUSH and FAMILY memories are never mixed.',
          ),
        _ConsentRow(
          icon: Icons.cloud_outlined,
          title: 'External communication',
          body:
              'Your message is sent over the internet to the configured provider for processing.',
        ),
        _ConsentRow(
          icon: Icons.policy_outlined,
          title: 'Provider-side handling',
          body:
              'The provider applies its own retention and data policies. External AI conversations are not completely private.',
        ),
        const SizedBox(height: AuraSpace.md),
        Text(
          'AURA never sends your PIN, credentials, unrelated integrations or dashboard telemetry to the model.',
          style: text.bodySmall?.copyWith(color: AuraColors.warning),
        ),
        const SizedBox(height: AuraSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            const SizedBox(width: AuraSpace.sm),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('I understand — allow'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConsentRow extends StatelessWidget {
  const _ConsentRow({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AuraSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: AuraColors.primary),
          const SizedBox(width: AuraSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AuraSpace.xxs),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemorySuggestionDraft {
  const _MemorySuggestionDraft({
    required this.content,
    required this.category,
  });

  final String content;
  final MemoryCategory category;
}

class _MemorySuggestionDialog extends StatefulWidget {
  const _MemorySuggestionDialog({required this.initialText});

  final String initialText;

  @override
  State<_MemorySuggestionDialog> createState() =>
      _MemorySuggestionDialogState();
}

class _MemorySuggestionDialogState extends State<_MemorySuggestionDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialText);
  MemoryCategory _category = MemoryCategory.preference;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Save to AURA Memory', style: text.headlineSmall),
        const SizedBox(height: AuraSpace.sm),
        Text(
          'This becomes a pending suggestion. Nothing is used by AURA until '
          'you approve it in the Memory workspace.',
          style: text.bodySmall?.copyWith(color: AuraColors.textSecondary),
        ),
        const SizedBox(height: AuraSpace.md),
        TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: 'Information to remember',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: AuraSpace.md),
        DropdownButtonFormField<MemoryCategory>(
          initialValue: _category,
          decoration: const InputDecoration(
            labelText: 'Category',
            border: OutlineInputBorder(),
          ),
          items: MemoryCategory.values
              .map(
                (MemoryCategory category) => DropdownMenuItem<MemoryCategory>(
                  value: category,
                  child: Text(category.label),
                ),
              )
              .toList(growable: false),
          onChanged: (MemoryCategory? value) {
            if (value != null) setState(() => _category = value);
          },
        ),
        const SizedBox(height: AuraSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final String content = _controller.text.trim();
                if (content.isEmpty) return;
                Navigator.of(context).pop(
                  _MemorySuggestionDraft(content: content, category: _category),
                );
              },
              child: const Text('Save as pending'),
            ),
          ],
        ),
      ],
    );
  }
}

class _RenameDialog extends StatelessWidget {
  const _RenameDialog({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Rename conversation',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AuraSpace.md),
        TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Title',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (String value) =>
              Navigator.of(context).pop(value.trim()),
        ),
        const SizedBox(height: AuraSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ConfirmDeleteDialog extends StatelessWidget {
  const _ConfirmDeleteDialog({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return _ConfirmationDialog(
      title: 'Delete conversation?',
      body: '“$title” and its locally stored messages will be removed.',
      confirmLabel: 'Delete',
    );
  }
}

class _ConfirmClearDialog extends StatelessWidget {
  const _ConfirmClearDialog();

  @override
  Widget build(BuildContext context) {
    return const _ConfirmationDialog(
      title: 'Clear messages?',
      body: 'All messages in this conversation will be removed locally. '
          'The conversation title and id stay in place.',
      confirmLabel: 'Clear',
    );
  }
}

class _ConfirmationDialog extends StatelessWidget {
  const _ConfirmationDialog({
    required this.title,
    required this.body,
    required this.confirmLabel,
  });

  final String title;
  final String body;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: AuraSpace.sm),
        Text(body, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: AuraSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(confirmLabel),
            ),
          ],
        ),
      ],
    );
  }
}

String _time(DateTime timestamp) {
  final String hour = timestamp.hour.toString().padLeft(2, '0');
  final String minute = timestamp.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _statusSummary(AiConnectionState connection, bool hasKey) {
  final String keyPart = hasKey ? 'Key stored in OS vault' : 'No key stored';
  final String testPart = switch (connection.status) {
    AiConnectionStatus.connected =>
      'Metadata verified ${connection.testedAt == null ? '' : _time(connection.testedAt!)}',
    AiConnectionStatus.needsRefresh =>
      'Verification expired or settings changed',
    AiConnectionStatus.testing => 'Verification request in progress',
    AiConnectionStatus.error => 'Last verification failed',
    AiConnectionStatus.disconnected ||
    AiConnectionStatus.unknown =>
      'No successful verification yet',
  };
  return '$keyPart · $testPart. /models access does not guarantee chat generation.';
}

String _connectionLabel(AiConnectionStatus status) {
  switch (status) {
    case AiConnectionStatus.unknown:
      return 'NOT TESTED';
    case AiConnectionStatus.testing:
      return 'TESTING';
    case AiConnectionStatus.connected:
      return 'METADATA VERIFIED';
    case AiConnectionStatus.disconnected:
      return 'NOT TESTED';
    case AiConnectionStatus.needsRefresh:
      return 'RETEST NEEDED';
    case AiConnectionStatus.error:
      return 'ERROR';
  }
}

Color _connectionColor(AiConnectionStatus status) {
  switch (status) {
    case AiConnectionStatus.connected:
      return AuraColors.success;
    case AiConnectionStatus.error:
      return AuraColors.danger;
    case AiConnectionStatus.needsRefresh:
      return AuraColors.warning;
    case AiConnectionStatus.testing:
      return AuraColors.primary;
    case AiConnectionStatus.unknown:
    case AiConnectionStatus.disconnected:
      return AuraColors.textSecondary;
  }
}
