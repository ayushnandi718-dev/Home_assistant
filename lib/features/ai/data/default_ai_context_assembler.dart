import 'package:aura_hub/features/ai/domain/ai_context.dart';
import 'package:aura_hub/features/ai/domain/ai_conversation.dart';
import 'package:aura_hub/features/ai/domain/ai_prompt_policy.dart';

/// Conservative replacement for provider-specific tokenizers.
///
/// Phase 1 uses a simple character heuristic. The abstraction is injectable so
/// a provider-aware estimator can replace it without touching the assembler.
class HeuristicAiTokenEstimator implements AiTokenEstimator {
  const HeuristicAiTokenEstimator({this.charactersPerToken = 4});

  final int charactersPerToken;

  @override
  int estimate(String text) {
    if (text.trim().isEmpty) return 0;
    final int perToken = charactersPerToken < 1 ? 1 : charactersPerToken;
    return (text.length / perToken).ceil();
  }
}

/// Default Phase 1 assembler: profile-scoped conversation history only.
///
/// It is pure and side-effect free. It never reads disk, credentials, vaults,
/// diagnostics or Family Directory data. Every source that is not explicitly
/// permitted by the caller is reported as unavailable, never transmitted.
class DefaultAiContextAssembler implements AiContextAssembler {
  const DefaultAiContextAssembler({
    this.estimator = const HeuristicAiTokenEstimator(),
    this.budget = const AiContextBudget(),
  });

  static const String _historyBoundary =
      'Use only the conversation history supplied with this request. Do not '
      'assume access to other profiles, private integrations, credentials, '
      'Family Directory records or external tools.';

  final AiTokenEstimator estimator;
  final AiContextBudget budget;

  @override
  AiAssembledContext assemble(AiContextRequest request) {
    final AiContextPolicy policy = request.policy;
    final List<String> systemInstructions = <String>[_historyBoundary];

    int usedTokens = estimator.estimate(
      AiPromptPolicy.systemInstruction(request.language),
    );
    for (final String instruction in systemInstructions) {
      usedTokens += estimator.estimate(instruction);
    }

    final Set<AiContextSource> included = <AiContextSource>{};
    final Set<AiContextSource> unavailable = <AiContextSource>{};

    if (policy.allowsHistoryFrom(request.historyProfile)) {
      included.add(AiContextSource.conversationHistory);
    } else {
      unavailable.add(AiContextSource.conversationHistory);
    }
    for (final AiContextSource source in AiContextSource.values) {
      if (!included.contains(source)) unavailable.add(source);
    }

    final int historyBudget =
        budget.maxTokens - budget.responseReserveTokens - usedTokens;
    final List<AiMessage> keptNewestFirst = <AiMessage>[];
    int historyTokens = 0;

    if (historyBudget <= 0) {
      included.remove(AiContextSource.conversationHistory);
      unavailable.add(AiContextSource.conversationHistory);
    } else if (included.contains(AiContextSource.conversationHistory)) {
      final List<AiMessage> eligible = request.history
          .where(
            (AiMessage message) =>
                (message.role == AiMessageRole.user ||
                    message.role == AiMessageRole.assistant) &&
                message.content.trim().isNotEmpty,
          )
          .toList(growable: false);

      // If the newest message cannot fit on its own, fail closed rather than
      // sending an incomplete prompt with unrelated older context.
      final bool newestOversized = eligible.isNotEmpty &&
          estimator.estimate(eligible.last.content) > historyBudget;
      if (newestOversized) {
        included.remove(AiContextSource.conversationHistory);
        unavailable.add(AiContextSource.conversationHistory);
      } else {
        for (final AiMessage message in eligible.reversed) {
          if (keptNewestFirst.length >= budget.maxMessages) break;
          final int cost = estimator.estimate(message.content);
          if (cost > historyBudget - historyTokens) continue;
          keptNewestFirst.add(message);
          historyTokens += cost;
        }
      }
    }

    return AiAssembledContext(
      messages: keptNewestFirst.reversed.toList(growable: false),
      systemInstructions: systemInstructions,
      includedSources: included,
      unavailableSources: unavailable,
      estimatedTokens: usedTokens + historyTokens,
      budgetTokens: budget.maxTokens,
    );
  }
}
