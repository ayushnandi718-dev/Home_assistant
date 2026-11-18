import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_memory_context.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';

/// Categories of information that may be considered for an AI request.
///
/// A source is never included merely because it exists. Every source must be
/// explicitly enabled in [AiContextPolicy] and must pass the profile rules
/// below. FAMILY Directory data is listed only as a future extension point:
/// Phase 1 never enables it, so it cannot reach a prompt.
enum AiContextSource { conversationHistory, approvedMemory, familyDirectory }

/// Explicit, fail-closed permission rules for context assembly.
class AiContextPolicy {
  const AiContextPolicy({
    required this.profile,
    this.enabledSources = const <AiContextSource>{
      AiContextSource.conversationHistory,
    },
    this.excludedSources = const <AiContextSource>{},
  });

  /// The active profile, not the profile that happens to own a data snapshot.
  final AuraProfile profile;

  final Set<AiContextSource> enabledSources;
  final Set<AiContextSource> excludedSources;

  bool allows(AiContextSource source) {
    if (!enabledSources.contains(source)) return false;
    if (excludedSources.contains(source)) return false;

    return switch (source) {
      // Conversation history is allowed only when its owning profile matches
      // the active profile. The caller supplies that scope separately.
      AiContextSource.conversationHistory => true,
      // Approved memories are supplied by the caller only after the profile,
      // approval and memory-retrieval checks have passed. The owning profile is
      // checked separately below.
      AiContextSource.approvedMemory => true,
      // Family Directory remains a separate source and is never AI context.
      AiContextSource.familyDirectory => false,
    };
  }

  /// Returns true only when [scope] is the active profile and history is allowed.
  bool allowsHistoryFrom(AuraProfile scope) =>
      scope == profile && allows(AiContextSource.conversationHistory);

  /// Returns true only when [scope] is the active profile and memory retrieval
  /// was explicitly enabled for that profile by the caller.
  bool allowsMemoryFrom(AuraProfile scope) =>
      scope == profile && allows(AiContextSource.approvedMemory);
}

/// Immutable input to the context assembly layer.
class AiContextRequest {
  const AiContextRequest({
    required this.profile,
    required this.historyProfile,
    required this.history,
    this.language = AiLanguage.auto,
    this.enabledSources = const <AiContextSource>{
      AiContextSource.conversationHistory,
    },
    this.excludedSources = const <AiContextSource>{},
    this.memories = const <AiMemoryContextItem>[],
    this.memoryProfile,
  });

  final AuraProfile profile;
  final AuraProfile historyProfile;
  final List<AiMessage> history;
  final AiLanguage language;

  /// Caller-owned approved-memory snapshot. Empty by default, so existing
  /// requests cannot accidentally gain a memory source.
  final List<AiMemoryContextItem> memories;

  /// Owning profile of [memories]. Must equal [profile] to be usable.
  final AuraProfile? memoryProfile;
  final Set<AiContextSource> enabledSources;
  final Set<AiContextSource> excludedSources;

  AiContextPolicy get policy => AiContextPolicy(
        profile: profile,
        enabledSources: enabledSources,
        excludedSources: excludedSources,
      );
}

/// Bounded, predictable context limits.
class AiContextBudget {
  const AiContextBudget({
    this.maxTokens = AuraRuntimeConfig.defaultAiContextTokens,
    this.responseReserveTokens = AuraRuntimeConfig.aiResponseReserveTokens,
    this.maxMessages = AuraRuntimeConfig.maxAiContextMessages,
  })  : assert(maxTokens > 0),
        assert(responseReserveTokens >= 0),
        assert(maxMessages >= 0);

  final int maxTokens;
  final int responseReserveTokens;
  final int maxMessages;
}

/// Replaceable token counter. Implementations must be deterministic and must
/// never inspect credentials, logs or any data outside the supplied text.
abstract class AiTokenEstimator {
  const AiTokenEstimator();

  int estimate(String text);
}

/// Safe, bounded output of the context assembly layer.
class AiAssembledContext {
  AiAssembledContext({
    required List<AiMessage> messages,
    required List<String> systemInstructions,
    required Set<AiContextSource> includedSources,
    required Set<AiContextSource> unavailableSources,
    required this.estimatedTokens,
    required this.budgetTokens,
    Set<String> includedMemoryIds = const <String>{},
  })  : messages = List<AiMessage>.unmodifiable(messages),
        systemInstructions = List<String>.unmodifiable(systemInstructions),
        includedSources = Set<AiContextSource>.unmodifiable(includedSources),
        unavailableSources =
            Set<AiContextSource>.unmodifiable(unavailableSources),
        includedMemoryIds = Set<String>.unmodifiable(includedMemoryIds);

  /// Oldest-to-newest, complete `user`/`assistant` messages only.
  final List<AiMessage> messages;

  /// Additional instructions appended after the existing base policy.
  final List<String> systemInstructions;

  final Set<AiContextSource> includedSources;
  final Set<AiContextSource> unavailableSources;

  /// Ids actually included in the request, after ranking and budgeting.
  final Set<String> includedMemoryIds;

  final int estimatedTokens;
  final int budgetTokens;

  bool get isEmpty => messages.isEmpty;
}

/// Prepares safe context before a provider request.
///
/// Implementations must not read credentials, diagnostics, logs, Family
/// Directory stores or any profile-scoped repository on behalf of the caller.
/// The caller owns data retrieval and passes an already-scoped snapshot.
abstract class AiContextAssembler {
  const AiContextAssembler();

  AiAssembledContext assemble(AiContextRequest request);
}
