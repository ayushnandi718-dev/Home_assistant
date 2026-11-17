import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/ai/domain/ai_language.dart';
import 'package:aura_hub/features/ai/domain/ai_provider_config.dart';
import 'package:aura_hub/features/ai/presentation/ai_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest AI foundation screen.
///
/// Nothing on this page contacts a model. No provider is connected, no paid
/// API is used by default, and no assistant reply is ever simulated.
class AiPage extends ConsumerWidget {
  const AiPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    final AiLanguage language = ref.watch(aiLanguageProvider);
    final AiReadiness readiness = ref.watch(aiReadinessProvider);
    final String statusLabel = readiness == AiReadiness.unconfigured
        ? 'NO PROVIDER CONFIGURED'
        : 'PROVIDER NOT IMPLEMENTED';

    return AuraScrollArea(
      padding: EdgeInsets.fromLTRB(
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.lg,
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageHeader(
                eyebrow: 'Experience / Foundation',
                title: 'AI Assistant',
                description:
                    'Design contracts for multilingual, tool-aware assistance. '
                    'This build contains the foundation only, not a working AI.',
                icon: Icons.auto_awesome_outlined,
                accent: AuraColors.secondary,
                trailing: StatusPill(
                  label: statusLabel,
                  color: AuraColors.textSecondary,
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'Foundation only — no AI is running',
                message:
                    'No provider is configured by default and no paid API is used '
                    'by this build. No credentials, network calls or model responses '
                    'are produced here. A real client adapter and explicit user '
                    'consent are required before any model is contacted.',
                icon: Icons.lock_outline_rounded,
                tone: AuraBannerTone.privacy,
              ),
              const SizedBox(height: AuraSpace.lg),
              Text('Supported provider kinds', style: text.titleLarge),
              const SizedBox(height: AuraSpace.xs),
              Text(
                'Informational only. None of these categories is connected.',
                style: text.bodyMedium,
              ),
              const SizedBox(height: AuraSpace.md),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final int columns = constraints.maxWidth >= 980
                      ? 3
                      : constraints.maxWidth >= 620
                          ? 2
                          : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: AuraSpace.md,
                      mainAxisSpacing: AuraSpace.md,
                      mainAxisExtent: 172,
                    ),
                    itemCount: AiProviderKind.values.length,
                    itemBuilder: (BuildContext context, int index) {
                      return _ProviderKindCard(
                        kind: AiProviderKind.values[index],
                      );
                    },
                  );
                },
              ),
              const SizedBox(height: AuraSpace.lg),
              _LanguageSelector(language: language, ref: ref),
              const SizedBox(height: AuraSpace.lg),
              Text('Conversation', style: text.titleLarge),
              const SizedBox(height: AuraSpace.md),
              const _EmptyConversationCard(),
              const SizedBox(height: AuraSpace.sm),
              const _DisabledComposer(),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderKindCard extends StatelessWidget {
  const _ProviderKindCard({required this.kind});

  final AiProviderKind kind;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.hub_outlined, size: 18, color: AuraColors.secondary),
              const Spacer(),
              const StatusPill(
                label: 'NOT CONNECTED',
                color: AuraColors.textSecondary,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(kind.label, style: text.titleSmall),
          const SizedBox(height: AuraSpace.xxs),
          Expanded(
            child: Text(
              '${kind.description} ${AiProviderConfig.capabilities}.',
              style: text.bodySmall,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSelector extends StatelessWidget {
  const _LanguageSelector({required this.language, required this.ref});

  final AiLanguage language;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.translate_outlined,
                  size: 18, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Text('Language preference', style: text.titleSmall),
            ],
          ),
          const SizedBox(height: AuraSpace.xs),
          Text(
            'A local preference only. It does not enable translation or generation.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AuraSpace.sm),
          Wrap(
            spacing: AuraSpace.xs,
            children: <Widget>[
              for (final AiLanguage option in AiLanguage.values)
                ChoiceChip(
                  label: Text('${option.label} (${option.code})'),
                  selected: option == language,
                  onSelected: (bool selected) {
                    if (selected) {
                      ref.read(aiLanguageProvider.notifier).state = option;
                    }
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyConversationCard extends StatelessWidget {
  const _EmptyConversationCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      child: SizedBox(
        width: double.infinity,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.chat_bubble_outline_rounded,
                size: 34, color: AuraColors.textSecondary),
            const SizedBox(height: AuraSpace.md),
            Text('No conversation', style: text.titleLarge),
            const SizedBox(height: AuraSpace.xs),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Text(
                'There is no model client in this build, so no messages are '
                'created and no assistant output is shown. This panel stays '
                'empty until a real provider adapter is implemented.',
                style: text.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisabledComposer extends StatelessWidget {
  const _DisabledComposer();

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          const Expanded(
            child: TextField(
              enabled: false,
              maxLines: 2,
              decoration: InputDecoration(
                hintText:
                    'Message input disabled until a real AI client is implemented',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: AuraSpace.sm),
          FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.send_outlined, size: 16),
            label: const Text('Send'),
          ),
        ],
      ),
    );
  }
}
