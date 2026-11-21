import 'dart:async';

import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/platform/platform_capabilities.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation_repository.dart';
import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';
import 'package:aura_hub/features/ai/domain/ai_input_policy.dart';
import 'package:aura_hub/features/ai/domain/ai_preferences.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_adapter.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_models.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_selection.dart';
import 'package:aura_hub/features/ai/data/ollama_ai_adapter.dart';
import 'package:aura_hub/features/ai/presentation/ai_markdown_view.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/features/ai/presentation/conversation_history_panel.dart';
import 'package:aura_hub/features/memory/domain/memory_category.dart';
import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
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

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool dense = auraDenseLayout(
          context,
          availableHeight: constraints.maxHeight,
        );
        final double screenWidth = MediaQuery.sizeOf(context).width;
        final bool mobile = screenWidth < AuraBreakpoints.mobile;
        final double horizontalPadding = pageHorizontalPadding(screenWidth);

        return Padding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            dense ? AuraSpace.xs : AuraSpace.lg,
            horizontalPadding,
            dense ? AuraSpace.xs : AuraSpace.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              // The whole workspace scrolls as one surface. The composer stays
              // pinned below it so the keyboard can never push it off screen.
              Expanded(
                child: Scrollbar(
                  controller: _messageScroll,
                  child: SingleChildScrollView(
                    controller: _messageScroll,
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        PageHeader(
                          eyebrow: 'Experience / Intelligence',
                          title: 'AURA Assistant',
                          description: mobile
                              ? null
                              : 'Streaming, multilingual help with explicit '
                                  'consent and local chat history.',
                          icon: Icons.auto_awesome_outlined,
                          accent: AuraColors.secondary,
                          compact: dense || mobile,
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
                            ],
                          ),
                        ),
                        if (mobile && !dense)
                          Padding(
                            padding: const EdgeInsets.only(
                              left: AuraSpace.xs,
                              top: AuraSpace.xs,
                            ),
                            child: Text(
                              'Streaming help with explicit consent and local chat history.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AuraColors.textSecondary),
                            ),
                          ),
                        SizedBox(height: dense ? AuraSpace.xxs : AuraSpace.sm),
                        // Actions are sized from the available width so long
                        // localised labels wrap to a second row instead of
                        // forcing a horizontal overflow.
                        LayoutBuilder(
                          builder: (BuildContext context,
                              BoxConstraints constraints) {
                            final double buttonWidth =
                                ((constraints.maxWidth - AuraSpace.sm) / 2)
                                    .clamp(120.0, 220.0);
                            return Wrap(
                              spacing: AuraSpace.sm,
                              runSpacing: AuraSpace.xs,
                              children: <Widget>[
                                SizedBox(
                                  width: buttonWidth,
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      minimumSize: const Size(0, 40),
                                    ),
                                    onPressed: () => setState(
                                        () => _showSettings = !_showSettings),
                                    icon: Icon(
                                      _showSettings
                                          ? Icons.chat_outlined
                                          : Icons.tune_outlined,
                                      size: 16,
                                    ),
                                    label: Text(_showSettings
                                        ? 'Back to chat'
                                        : 'Provider'),
                                  ),
                                ),
                                SizedBox(
                                  width: buttonWidth,
                                  child: FilledButton.icon(
                                    style: FilledButton.styleFrom(
                                      minimumSize: const Size(0, 40),
                                    ),
                                    onPressed: _newConversation,
                                    icon: const Icon(
                                      Icons.add_outlined,
                                      size: 16,
                                    ),
                                    label: const Text('New chat'),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        SizedBox(height: dense ? AuraSpace.xxs : AuraSpace.sm),
                        // Collapsed only while the keyboard is open; the consent
                        // banner returns as soon as the input closes. Consent is
                        // never granted or implied by this layout decision.
                        if (!preferences.consentGranted && !dense)
                          InfoBanner(
                            title: 'External AI requests are off',
                            message:
                                'Conversations stay local until you approve a request to '
                                '${config?.label ?? 'the configured provider'}. '
                                'You can revoke consent in Provider settings.',
                            icon: Icons.privacy_tip_outlined,
                            tone: AuraBannerTone.privacy,
                            trailing: TextButton(
                              onPressed: () => _ensureConsent(config),
                              child: const Text('Review'),
                            ),
                          ),
                        SizedBox(height: dense ? AuraSpace.xs : AuraSpace.md),
                        _showSettings
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
                                onPrompt: _usePrompt,
                                onNew: _newConversation,
                                onSelect: _selectConversation,
                                onRename: _renameConversation,
                                onDelete: _deleteConversation,
                                onClear: _clearConversation,
                                onCopy: _copy,
                                onRemember: _remember,
                                dense: dense,
                              ),
                      ],
                    ),
                  ),
                ),
              ),
              if (chat.hasError)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AuraSpace.lg),
                  child: _ErrorBanner(
                    message: chat.errorMessage ?? 'The request failed.',
                    canRetry: chat.failureKind?.isRetryable ?? false,
                    onRetry: () =>
                        ref.read(activeAiChatControllerProvider).retry(),
                  ),
                ),
              SizedBox(height: dense ? AuraSpace.xxs : AuraSpace.sm),
              _Composer(
                controller: _composer,
                focusNode: _composerFocus,
                isBusy: chat.isBusy,
                onSend: _send,
                onCancel: () =>
                    ref.read(activeAiChatControllerProvider).cancel(),
                dense: dense,
              ),
            ],
          ),
        );
      },
    );
  }
}

Color _readinessColor(AiReadiness readiness) {
  switch (readiness) {
    case AiReadiness.connected:
      return AuraColors.success;
    case AiReadiness.error:
    case AiReadiness.unavailable:
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
    required this.onPrompt,
    required this.onNew,
    required this.onSelect,
    required this.onRename,
    required this.onDelete,
    required this.onClear,
    required this.onCopy,
    required this.onRemember,
    required this.dense,
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
  final void Function(String prompt) onPrompt;
  final Future<void> Function() onNew;
  final Future<void> Function(String id) onSelect;
  final Future<void> Function(AiConversation conversation) onRename;
  final Future<void> Function(AiConversation conversation) onDelete;
  final Future<void> Function() onClear;
  final Future<void> Function(String content) onCopy;
  final Future<void> Function(AiMessage message, String content) onRemember;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 980;
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (wide) ...<Widget>[
              SizedBox(
                width: 272,
                height: 520,
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
                onPrompt: onPrompt,
                onNew: onNew,
                onSelect: onSelect,
                onHistory: onHistory,
                onClear: onClear,
                onCopy: onCopy,
                onRemember: onRemember,
                compact: !wide,
                dense: dense,
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
    required this.onPrompt,
    required this.onNew,
    required this.onSelect,
    required this.onHistory,
    required this.onClear,
    required this.onCopy,
    required this.onRemember,
    required this.compact,
    required this.dense,
  });

  final AuraProfile profile;
  final AiPreferences preferences;
  final List<AiProviderConfig> configs;
  final AiProviderConfig? config;
  final AiChatState chat;
  final void Function(String prompt) onPrompt;
  final Future<void> Function() onNew;
  final Future<void> Function(String id) onSelect;
  final Future<void> Function() onHistory;
  final Future<void> Function() onClear;
  final Future<void> Function(String content) onCopy;
  final Future<void> Function(AiMessage message, String content) onRemember;
  final bool compact;
  final bool dense;

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
            padding: EdgeInsets.fromLTRB(
              dense ? AuraSpace.md : AuraSpace.lg,
              dense ? AuraSpace.xs : AuraSpace.md,
              dense ? AuraSpace.xs : AuraSpace.md,
              dense ? AuraSpace.xs : AuraSpace.md,
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: dense ? 32 : 38,
                  height: dense ? 32 : 38,
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
          messages.isEmpty && chat.streamingText == null
              ? _EmptyConversation(onPrompt: onPrompt, compact: compact)
              : ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
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
                  child: isUser
                      ? Text(message.content, style: text.bodyMedium)
                      : AiMarkdownView(text: message.content),
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
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          return ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: constraints.maxWidth < 640 ? constraints.maxWidth : 640,
            ),
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
                  SelectionArea(
                    child: AiMarkdownView(text: text, streaming: true),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EmptyConversation extends StatelessWidget {
  const _EmptyConversation({
    required this.onPrompt,
    this.compact = false,
  });

  final void Function(String prompt) onPrompt;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AuraSpace.lg),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            // Prompt cards shrink with the available width instead of forcing
            // a 300px row on 320/360 logical-pixel phones.
            final double cardWidth =
                constraints.maxWidth < 300 ? constraints.maxWidth : 300;
            return ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Container(
                    width: compact ? 48 : 64,
                    height: compact ? 48 : 64,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: <Color>[
                          AuraColors.primary,
                          AuraColors.secondary
                        ],
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: AuraColors.secondary.withValues(alpha: 0.24),
                          blurRadius: compact ? 18 : 32,
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.auto_awesome_rounded,
                      color: AuraColors.onAccent,
                      size: compact ? 22 : 28,
                    ),
                  ),
                  SizedBox(height: compact ? AuraSpace.md : AuraSpace.lg),
                  Text(
                    'Where should we begin?',
                    style: compact ? text.titleLarge : text.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: compact ? AuraSpace.xxs : AuraSpace.sm),
                  Text(
                    compact
                        ? 'Choose a prompt or write your own. Nothing is sent '
                            'until you press Send and consent is in place.'
                        : 'Choose a prompt to place it in the composer, or write your own. '
                            'Nothing is sent until you press Send and consent is in place.',
                    style: compact ? text.bodySmall : text.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: compact ? AuraSpace.md : AuraSpace.lg),
                  Wrap(
                    spacing: AuraSpace.sm,
                    runSpacing: AuraSpace.sm,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      for (final String prompt in _examplePrompts)
                        SizedBox(
                          width: cardWidth,
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
            );
          },
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
    required this.dense,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isBusy;
  final Future<void> Function() onSend;
  final VoidCallback onCancel;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.fromLTRB(
        dense ? AuraSpace.sm : AuraSpace.lg,
        0,
        dense ? AuraSpace.sm : AuraSpace.lg,
        dense ? AuraSpace.xs : AuraSpace.lg,
      ),
      padding: EdgeInsets.all(dense ? AuraSpace.xs : AuraSpace.sm),
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
                // Multiline input is preserved; while the keyboard is open
                // the field scrolls internally after three visible lines so
                // it cannot consume the whole chat viewport.
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: dense ? 96 : double.infinity,
                  ),
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                    enabled: !isBusy,
                    maxLines: dense ? 3 : 5,
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
          // Purely explanatory. It returns as soon as the keyboard closes.
          if (!dense) ...<Widget>[
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
        ],
      ),
    );
  }
}

/// Truthful per-provider overview. A saved provider, the selected provider, a
/// verified provider and the provider used by the next request are deliberately
/// shown as four separate facts.
class _ProviderOverviewCard extends ConsumerWidget {
  const _ProviderOverviewCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool ollamaAvailable = ref.watch(localOllamaAvailableProvider);
    const Widget groqCard = _ProviderCard(
      kind: AiProviderKind.openAiCompatible,
      title: 'Groq',
      description:
          'Cloud inference through the existing OpenAI-compatible adapter.',
      icon: Icons.cloud_outlined,
      cloud: true,
    );
    const Widget ollamaCard = _ProviderCard(
      kind: AiProviderKind.localOllama,
      title: 'Ollama',
      description: 'Local models through the native loopback-only adapter.',
      icon: Icons.computer_outlined,
      cloud: false,
    );
    const Widget unavailableNotice = InfoBanner(
      title: 'Local models are desktop-only',
      message:
          'Ollama needs a loopback service on the host computer. Android keeps '
          'this provider in shared code but does not expose it here.',
      icon: Icons.computer_outlined,
      tone: AuraBannerTone.warning,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 760;
        return SurfaceCard(
          padding: const EdgeInsets.all(AuraSpace.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.dashboard_customize_outlined,
                      size: 20, color: AuraColors.primary),
                  const SizedBox(width: AuraSpace.sm),
                  Text('Provider management',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: AuraSpace.xs),
              Text(
                'Select, discover and verify providers for this workspace. '
                'Connection tests check metadata only and never send a message.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: AuraSpace.md),
              if (wide)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Expanded(child: groqCard),
                    const SizedBox(width: AuraSpace.md),
                    Expanded(
                      child: ollamaAvailable ? ollamaCard : unavailableNotice,
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    groqCard,
                    const SizedBox(height: AuraSpace.md),
                    ollamaAvailable ? ollamaCard : unavailableNotice,
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}

AiProviderConfig? _cardConfig(
  List<AiProviderConfig> configs,
  AiPreferences preferences,
  AiProviderConfig? nextConfig,
  AiProviderKind kind,
) {
  if (nextConfig != null && nextConfig.kind == kind) return nextConfig;
  final String? selectedId = preferences.selectedProviderId;
  if (selectedId != null) {
    for (final AiProviderConfig config in configs) {
      if (config.id == selectedId && config.kind == kind) return config;
    }
  }
  for (final AiProviderConfig config in configs) {
    if (config.kind == kind) return config;
  }
  return null;
}

class _ProviderCard extends ConsumerWidget {
  const _ProviderCard({
    required this.kind,
    required this.title,
    required this.description,
    required this.icon,
    required this.cloud,
  });

  final AiProviderKind kind;
  final String title;
  final String description;
  final IconData icon;
  final bool cloud;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final List<AiProviderConfig> configs = ref.watch(activeAiConfigsProvider);
    final AiPreferences preferences = ref.watch(activeAiPreferencesProvider);
    final AiProviderConfig? nextConfig =
        ref.watch(activeAiRequestConfigProvider);
    final AiProviderConfig? config =
        _cardConfig(configs, preferences, nextConfig, kind);
    final String providerId = config?.id ?? '';
    final AiConnectionState connection =
        ref.watch(activeAiConnectionStatusForProvider(providerId));
    final AiModelCatalogEntry catalog =
        ref.watch(activeAiModelsForProvider(providerId));
    final AiCredentialState credentials =
        ref.watch(activeAiCredentialStateProvider);

    final bool isSelected =
        config != null && preferences.selectedProviderId == config.id;
    final bool isNext = config != null && nextConfig?.id == config.id;
    final bool keyKnownForCard = config != null &&
        (isSelected || isNext) &&
        credentials.presence != AiCredentialPresence.unknown;

    return Semantics(
      container: true,
      label:
          '$title provider, ${isNext ? 'used by the next request' : 'not used by the next request'}',
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AuraRadius.card),
          border: Border.all(
            color: isNext ? AuraColors.secondary : AuraColors.border,
          ),
        ),
        padding: const EdgeInsets.all(AuraSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Icon(icon, size: 20, color: AuraColors.secondary),
                const SizedBox(width: AuraSpace.sm),
                Expanded(
                  child: Text(title, style: text.titleMedium),
                ),
                Chip(
                  visualDensity: VisualDensity.compact,
                  label: Text(
                    cloud ? 'Cloud' : 'Local',
                    style: text.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AuraSpace.xxs),
            Text(description, style: text.bodySmall),
            const SizedBox(height: AuraSpace.sm),
            Wrap(
              spacing: AuraSpace.xs,
              runSpacing: AuraSpace.xs,
              children: <Widget>[
                _chip(
                  context,
                  config == null ? 'NOT CONFIGURED' : 'CONFIGURED',
                  config == null
                      ? AuraColors.textSecondary
                      : AuraColors.primary,
                ),
                if (isSelected)
                  _chip(context, 'SELECTED', AuraColors.secondary),
                if (isNext) _chip(context, 'NEXT REQUEST', AuraColors.success),
              ],
            ),
            const SizedBox(height: AuraSpace.sm),
            _InfoRow(
              label: cloud ? 'Endpoint' : 'Local endpoint',
              value: config?.baseUrl ??
                  (cloud ? 'Not configured' : OllamaAiAdapter.defaultBaseUrl),
            ),
            _InfoRow(
              label: 'Model',
              value: config?.model.isNotEmpty == true
                  ? config!.model
                  : 'No model selected',
            ),
            if (cloud)
              _InfoRow(
                label: 'Credential',
                value: keyKnownForCard
                    ? (credentials.presence == AiCredentialPresence.present
                        ? 'Stored in OS vault'
                        : 'No key for this workspace')
                    : 'Not checked for this provider',
              )
            else
              _InfoRow(
                label: 'Installed models',
                value: catalog.models.isEmpty
                    ? 'Not loaded'
                    : '${catalog.models.length}',
              ),
            const SizedBox(height: AuraSpace.xs),
            Row(
              children: <Widget>[
                GlassStatusBadge(
                  label: _cardConnectionLabel(connection),
                  color: _cardConnectionColor(connection),
                  dense: true,
                ),
                const SizedBox(width: AuraSpace.xs),
                Expanded(
                  child: Text(
                    _cardModelStatus(catalog),
                    style: text.labelSmall?.copyWith(
                      color: AuraColors.textSecondary,
                    ),
                  ),
                ),
              ],
            ),
            if (connection.message != null) ...<Widget>[
              const SizedBox(height: AuraSpace.xs),
              Text(connection.message!, style: text.bodySmall),
            ],
            if (catalog.message != null &&
                catalog.status != AiModelLoadStatus.idle) ...<Widget>[
              const SizedBox(height: AuraSpace.xs),
              Text(
                catalog.message!,
                style: text.bodySmall?.copyWith(color: AuraColors.warning),
              ),
            ],
            if (config != null && catalog.models.isNotEmpty) ...<Widget>[
              const SizedBox(height: AuraSpace.sm),
              DropdownButtonFormField<String>(
                initialValue: catalog.models
                        .any((AiModelInfo item) => item.id == config.model)
                    ? config.model
                    : null,
                isExpanded: true,
                hint: const Text('Select a model'),
                decoration: const InputDecoration(
                  labelText: 'Available models',
                  border: OutlineInputBorder(),
                ),
                items: <DropdownMenuItem<String>>[
                  for (final AiModelInfo model in catalog.models)
                    DropdownMenuItem<String>(
                      value: model.id,
                      child: Text(
                        model.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (String? value) {
                  if (value == null) return;
                  unawaited(
                      _applyProviderModel(context, ref, config.id, value));
                },
              ),
            ],
            const SizedBox(height: AuraSpace.sm),
            Wrap(
              spacing: AuraSpace.xs,
              runSpacing: AuraSpace.xs,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: config == null || isNext
                      ? null
                      : () => unawaited(_activateProvider(ref, config.id)),
                  icon: Icon(
                    isNext
                        ? Icons.check_circle_outline
                        : Icons.arrow_forward_ios,
                    size: 14,
                  ),
                  label: Text(
                    isNext ? 'Next request' : 'Select provider',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: config == null ||
                          connection.status == AiConnectionStatus.testing
                      ? null
                      : () => ref
                          .read(activeAiConnectionControllerProvider)
                          .test(providerId: config.id),
                  icon: connection.status == AiConnectionStatus.testing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.network_check_outlined, size: 14),
                  label: Text(
                    connection.status == AiConnectionStatus.testing
                        ? 'Testing…'
                        : 'Test connection',
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: config == null || catalog.isLoading
                      ? null
                      : () => ref
                          .read(activeAiConnectionControllerProvider)
                          .refreshModels(providerId: config.id),
                  icon: catalog.isLoading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          cloud ? Icons.list_alt_outlined : Icons.refresh,
                          size: 14,
                        ),
                  label: Text(
                    catalog.isLoading
                        ? 'Loading…'
                        : (cloud ? 'Load models' : 'Refresh models'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Widget _chip(BuildContext context, String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AuraSpace.xs,
        vertical: AuraSpace.xxs / 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AuraRadius.pill),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Widget labelText = Text(
      label,
      style: text.labelSmall?.copyWith(color: AuraColors.textSecondary),
    );
    final Widget valueText = Text(
      value,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: text.bodySmall,
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        if (constraints.maxWidth < 620) {
          return Padding(
            padding: const EdgeInsets.only(bottom: AuraSpace.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                labelText,
                const SizedBox(height: AuraSpace.xxs),
                valueText,
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: AuraSpace.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 104),
                child: labelText,
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: valueText),
            ],
          ),
        );
      },
    );
  }
}

/// Switching providers cancels an in-flight generation through the existing
/// cancellation token. History and the active conversation are untouched.
Future<void> _activateProvider(WidgetRef ref, String? providerId) =>
    ref.read(activeAiProviderSwitchCoordinatorProvider).switchTo(providerId);

Future<void> _applyProviderModel(
  BuildContext context,
  WidgetRef ref,
  String providerId,
  String modelId,
) async {
  final bool saved = await ref
      .read(activeAiConfigsControllerProvider)
      .selectModel(providerId, modelId);
  if (!saved || !context.mounted) return;
  ref
      .read(activeAiConnectionControllerProvider)
      .invalidate(providerId: providerId);
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Model selected for this provider.')),
  );
}

String _cardConnectionLabel(AiConnectionState state) {
  switch (state.status) {
    case AiConnectionStatus.testing:
      return 'TESTING';
    case AiConnectionStatus.connected:
      return 'AVAILABLE';
    case AiConnectionStatus.error:
      return switch (state.failureKind) {
        AiFailureKind.authentication ||
        AiFailureKind.permissionDenied =>
          'AUTH ERROR',
        AiFailureKind.configuration ||
        AiFailureKind.needsConfiguration ||
        AiFailureKind.missingCredentials ||
        AiFailureKind.unsupportedProvider =>
          'CONFIG ERROR',
        AiFailureKind.timeout || AiFailureKind.connectionTimeout => 'TIMED OUT',
        _ => 'UNAVAILABLE',
      };
    case AiConnectionStatus.needsRefresh:
      return 'RETEST NEEDED';
    case AiConnectionStatus.disconnected:
    case AiConnectionStatus.unknown:
      return 'NOT TESTED';
  }
}

Color _cardConnectionColor(AiConnectionState state) {
  switch (state.status) {
    case AiConnectionStatus.connected:
      return AuraColors.success;
    case AiConnectionStatus.testing:
      return AuraColors.primary;
    case AiConnectionStatus.needsRefresh:
      return AuraColors.warning;
    case AiConnectionStatus.error:
      return AuraColors.danger;
    case AiConnectionStatus.disconnected:
    case AiConnectionStatus.unknown:
      return AuraColors.textSecondary;
  }
}

String _cardModelStatus(AiModelCatalogEntry catalog) {
  switch (catalog.status) {
    case AiModelLoadStatus.idle:
      return 'Models not loaded';
    case AiModelLoadStatus.loading:
      return 'Loading model list…';
    case AiModelLoadStatus.loaded:
      return '${catalog.models.length} available';
    case AiModelLoadStatus.noModels:
      return 'No models installed';
    case AiModelLoadStatus.unavailable:
      return 'Provider unavailable';
    case AiModelLoadStatus.error:
      return 'Model list unavailable';
  }
}

class _ProviderSettingsPanel extends ConsumerWidget {
  const _ProviderSettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bool ollamaAvailable = ref.watch(localOllamaAvailableProvider);
    final List<AiProviderConfig> allConfigs =
        ref.watch(activeAiConfigsProvider);
    final List<AiProviderConfig> configs = ollamaAvailable
        ? allConfigs
        : allConfigs
            .where((AiProviderConfig item) => !item.isLocal)
            .toList(growable: false);
    final AiPreferences preferences = ref.watch(activeAiPreferencesProvider);
    final String? preferredId = preferences.selectedProviderId ??
        (configs.isEmpty ? null : configs.first.id);
    final String? selectedId = preferredId != null &&
            configs.any((AiProviderConfig item) => item.id == preferredId)
        ? preferredId
        : null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const InfoBanner(
              title: 'Credentials stay in the operating-system vault',
              message:
                  'Only the endpoint, model and a credential reference are stored. '
                  'Connection status appears after a real request succeeds.',
              icon: Icons.key_outlined,
              tone: AuraBannerTone.privacy,
            ),
            if (!ollamaAvailable) ...<Widget>[
              const SizedBox(height: AuraSpace.md),
              const InfoBanner(
                title: 'Local models are desktop-only',
                message:
                    'Ollama needs a loopback service on the host computer. '
                    'Android keeps the adapter in shared code but does not '
                    'allow it to be selected or tested here.',
                icon: Icons.computer_outlined,
                tone: AuraBannerTone.warning,
              ),
            ],
            const SizedBox(height: AuraSpace.md),
            const _ProviderOverviewCard(),
            const SizedBox(height: AuraSpace.md),
            _ProviderSettingsForm(
              key: ValueKey<String?>(selectedId),
              configs: configs,
              selectedId: selectedId,
              ollamaAvailable: ollamaAvailable,
            ),
            const SizedBox(height: AuraSpace.md),
            const _PrivacyControlCard(),
            const SizedBox(height: AuraSpace.md),
            const _ToolExtensionCard(),
          ],
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
    required this.ollamaAvailable,
  });

  final List<AiProviderConfig> configs;
  final String? selectedId;
  final bool ollamaAvailable;

  @override
  ConsumerState<_ProviderSettingsForm> createState() =>
      _ProviderSettingsFormState();
}

class _ProviderSettingsFormState extends ConsumerState<_ProviderSettingsForm> {
  late final TextEditingController _label;
  late final TextEditingController _baseUrl;
  late final TextEditingController _model;
  final TextEditingController _apiKey = TextEditingController();
  late AiProviderKind _kind;
  bool _obscureKey = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final AiProviderConfig? config = _currentConfig();
    _kind = config?.kind ?? AiProviderKind.openAiCompatible;
    _label = TextEditingController(
      text: config?.label ??
          (_kind == AiProviderKind.localOllama ? 'Local Ollama' : 'Groq'),
    );
    _baseUrl = TextEditingController(
      text: config?.baseUrl ??
          (_kind == AiProviderKind.localOllama
              ? OllamaAiAdapter.defaultBaseUrl
              : 'https://api.groq.com/openai/v1'),
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
    _kind = AiProviderKind.openAiCompatible;
    _label.text = 'Groq';
    // Base URL is public configuration; the model is intentionally left blank
    // because available model ids change and must be discovered or chosen.
    _baseUrl.text = 'https://api.groq.com/openai/v1';
    setState(() {});
  }

  void _useOllamaPreset() {
    if (!widget.ollamaAvailable) return;
    _kind = AiProviderKind.localOllama;
    _label.text = 'Local Ollama';
    _baseUrl.text = OllamaAiAdapter.defaultBaseUrl;
    _model.clear();
    setState(() {});
  }

  AiProviderConfig _draftConfig() {
    final AiProviderConfig? existing = _currentConfig();
    return AiProviderConfig(
      id: existing?.id ??
          (_kind == AiProviderKind.localOllama ? 'ollama' : 'groq'),
      label: _label.text.trim(),
      kind: _kind,
      baseUrl: _baseUrl.text.trim(),
      model: _model.text.trim(),
      enabled: true,
      language: ref.read(activeAiPreferencesProvider).language,
    );
  }

  Future<void> _discover() async {
    if (_kind == AiProviderKind.localOllama && !widget.ollamaAvailable) {
      _toast(AiProviderManagementMessages.ollamaAndroidUnavailable);
      return;
    }
    final AiProviderConfig draft = _draftConfig();
    final String? error = draft.validateEndpoint();
    if (error != null) {
      _toast(error);
      return;
    }
    await ref.read(activeAiConnectionControllerProvider).discoverModels(draft);
  }

  Future<void> _save() async {
    if (_saving) return;
    if (_kind == AiProviderKind.localOllama && !widget.ollamaAvailable) {
      _toast(AiProviderManagementMessages.ollamaAndroidUnavailable);
      return;
    }
    final AiProviderConfig config = _draftConfig();
    final String? error =
        config.validate() ?? AiProviderSelection.validateModelId(config.model);
    if (error != null) {
      _toast(error);
      return;
    }
    setState(() => _saving = true);

    await ref.read(activeAiConfigsControllerProvider).upsert(config);
    if (!config.isLocal) {
      final String key = _apiKey.text.trim();
      if (key.isNotEmpty) {
        await ref.read(activeAiCredentialControllerProvider).save(
              providerId: config.id,
              apiKey: key,
            );
        _apiKey.clear();
      }
    }
    await _activateProvider(ref, config.id);
    if (!mounted) return;
    setState(() => _saving = false);
    _toast('Provider saved locally. Test the connection to verify it.');
  }

  Future<void> _test() async {
    if (_kind == AiProviderKind.localOllama && !widget.ollamaAvailable) {
      _toast(AiProviderManagementMessages.ollamaAndroidUnavailable);
      return;
    }
    final AiProviderConfig? config = _currentConfig();
    final String? error = config?.validateEndpoint();
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
    final bool isLocal = _kind == AiProviderKind.localOllama;
    final bool ollamaBlocked = isLocal && !widget.ollamaAvailable;
    final bool hasKey =
        !isLocal && credentials.presence == AiCredentialPresence.present;
    final AiProviderConfig? current = _currentConfig();
    final String catalogId = current?.id ?? (isLocal ? 'ollama' : 'groq');
    final AiConnectionState connection =
        ref.watch(activeAiConnectionStatusForProvider(catalogId));
    final AiModelCatalogEntry catalog =
        ref.watch(activeAiModelsForProvider(catalogId));

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget badge = GlassStatusBadge(
                label: _connectionLabel(connection.status),
                color: _connectionColor(connection.status),
                dense: true,
              );
              final Widget heading = Row(
                children: <Widget>[
                  Icon(Icons.hub_outlined,
                      color: AuraColors.secondary, size: 20),
                  const SizedBox(width: AuraSpace.sm),
                  Expanded(
                    child: Text(
                      'Provider configuration',
                      style: text.titleLarge,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              );
              if (constraints.maxWidth < 620) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    heading,
                    const SizedBox(height: AuraSpace.xs),
                    badge,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  // The heading itself contains an Expanded title, so it must
                  // receive a bounded width from this outer Row.
                  Expanded(child: heading),
                  const SizedBox(width: AuraSpace.sm),
                  badge,
                ],
              );
            },
          ),
          if (ollamaBlocked) ...<Widget>[
            const SizedBox(height: AuraSpace.md),
            const InfoBanner(
              title: 'Local Ollama is unavailable on Android',
              message: AiProviderManagementMessages.ollamaAndroidUnavailable,
              icon: Icons.computer_outlined,
              tone: AuraBannerTone.warning,
            ),
          ],
          const SizedBox(height: AuraSpace.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double fieldWidth =
                  constraints.maxWidth < 340 ? constraints.maxWidth : 340;
              return Wrap(
                spacing: AuraSpace.sm,
                runSpacing: AuraSpace.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: fieldWidth,
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
                        unawaited(_activateProvider(ref, value));
                      },
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _useGroqPreset,
                    icon: const Icon(Icons.bolt_outlined, size: 16),
                    label: const Text('Use Groq endpoint'),
                  ),
                  OutlinedButton.icon(
                    onPressed: widget.ollamaAvailable ? _useOllamaPreset : null,
                    icon: const Icon(Icons.computer_outlined, size: 16),
                    label: const Text('Use local Ollama'),
                  ),
                ],
              );
            },
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
            decoration: InputDecoration(
              labelText:
                  isLocal ? 'Local endpoint' : 'OpenAI-compatible base URL',
              border: const OutlineInputBorder(),
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
          const SizedBox(height: AuraSpace.sm),
          Wrap(
            spacing: AuraSpace.xs,
            runSpacing: AuraSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed:
                    catalog.isLoading || ollamaBlocked ? null : _discover,
                icon: catalog.isLoading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search_outlined, size: 16),
                label: Text(
                  catalog.isLoading
                      ? 'Loading…'
                      : (isLocal ? 'Refresh installed models' : 'Load models'),
                ),
              ),
              Text(
                _cardModelStatus(catalog),
                style:
                    text.labelSmall?.copyWith(color: AuraColors.textSecondary),
              ),
            ],
          ),
          if (catalog.message != null &&
              catalog.status != AiModelLoadStatus.idle) ...<Widget>[
            const SizedBox(height: AuraSpace.xs),
            Text(
              catalog.message!,
              style: text.bodySmall?.copyWith(color: AuraColors.warning),
            ),
          ],
          if (catalog.models.isNotEmpty) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            DropdownButtonFormField<String>(
              initialValue: catalog.models
                      .any((AiModelInfo item) => item.id == _model.text.trim())
                  ? _model.text.trim()
                  : null,
              isExpanded: true,
              hint: const Text('Choose a discovered model'),
              decoration: const InputDecoration(
                labelText: 'Discovered models',
                border: OutlineInputBorder(),
              ),
              items: <DropdownMenuItem<String>>[
                for (final AiModelInfo model in catalog.models)
                  DropdownMenuItem<String>(
                    value: model.id,
                    child: Text(model.label, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (String? value) {
                if (value == null) return;
                setState(() => _model.text = value);
              },
            ),
          ],
          if (!isLocal) ...<Widget>[
            const SizedBox(height: AuraSpace.md),
            TextField(
              controller: _apiKey,
              obscureText: _obscureKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: hasKey ? 'Replace API key' : 'API key',
                hintText:
                    hasKey ? 'Leave blank to keep the stored key' : 'sk-…',
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
          ],
          if (isLocal && widget.ollamaAvailable)
            Padding(
              padding: const EdgeInsets.only(top: AuraSpace.md),
              child: Text(
                'Local Ollama uses a numeric loopback address only. No API key or '
                'Authorization header is stored or sent.',
                style:
                    text.labelSmall?.copyWith(color: AuraColors.textSecondary),
              ),
            ),
          if (connection.message != null) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            Text(connection.message!, style: text.bodySmall),
          ],
          const SizedBox(height: AuraSpace.sm),
          Text(
            _statusSummary(connection, hasKey, isLocal),
            style: text.labelSmall?.copyWith(color: AuraColors.textSecondary),
          ),
          const SizedBox(height: AuraSpace.md),
          Wrap(
            spacing: AuraSpace.sm,
            runSpacing: AuraSpace.sm,
            children: <Widget>[
              FilledButton.icon(
                onPressed: _saving || ollamaBlocked ? null : _save,
                icon: const Icon(Icons.save_outlined, size: 16),
                label: Text(_saving ? 'Saving…' : 'Save provider'),
              ),
              OutlinedButton.icon(
                onPressed: ollamaBlocked ||
                        connection.status == AiConnectionStatus.testing
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
            'A successful test makes a real metadata request only; no conversation '
            'content is sent and chat generation is not verified. Saving a key '
            'alone never marks the provider connected.',
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

String _statusSummary(
  AiConnectionState connection,
  bool hasKey,
  bool isLocal,
) {
  final String keyPart = isLocal
      ? 'No credential used'
      : (hasKey ? 'Key stored in OS vault' : 'No key stored');
  final String testPart = switch (connection.status) {
    AiConnectionStatus.connected =>
      'Provider reachable ${connection.testedAt == null ? '' : _time(connection.testedAt!)}',
    AiConnectionStatus.needsRefresh =>
      'Verification expired or settings changed',
    AiConnectionStatus.testing => 'Verification request in progress',
    AiConnectionStatus.error => 'Last verification failed',
    AiConnectionStatus.disconnected ||
    AiConnectionStatus.unknown =>
      'No successful verification yet',
  };
  final String probe = isLocal ? '/api/tags' : '/models';
  return '$keyPart · $testPart. $probe access does not guarantee chat generation.';
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
