import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/integrations/domain/integration_service.dart';
import 'package:aura_hub/features/integrations/domain/integration_status.dart';
import 'package:aura_hub/features/integrations/presentation/integration_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest integration browser. Every service is shown as disconnected because
/// no adapter, OAuth client or secure token store exists in this milestone.
class IntegrationsPage extends ConsumerWidget {
  const IntegrationsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<IntegrationDefinition> definitions =
        ref.watch(integrationCatalogProvider);
    final Map<IntegrationService, IntegrationStatus> statuses =
        ref.watch(integrationStatusProvider);
    final IntegrationReadiness readiness =
        ref.watch(integrationReadinessProvider);
    final double padding =
        pageHorizontalPadding(MediaQuery.sizeOf(context).width);

    return AuraScrollArea(
      padding:
          EdgeInsets.fromLTRB(padding, AuraSpace.lg, padding, AuraSpace.xxl),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageHeader(
                eyebrow: 'Experience',
                title: 'Integrations',
                description:
                    'The services that will give AURA context. Connections are '
                    'added one at a time, never simulated.',
                icon: Icons.extension_outlined,
                accent: AuraColors.primary,
                trailing: StatusPill(
                  label: readiness == IntegrationReadiness.noAdapters
                      ? 'NO ADAPTERS YET'
                      : 'ADAPTERS AVAILABLE',
                  color: AuraColors.textSecondary,
                  showDot: false,
                  dense: true,
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'Nothing is connected',
                message:
                    'These are planned capabilities, not live accounts. No '
                    'OAuth client, API key or token store exists yet. When a '
                    'service is added it will appear here as connected only '
                    'after a real authorization succeeds.',
                icon: Icons.lock_outline_rounded,
                tone: AuraBannerTone.privacy,
              ),
              const SizedBox(height: AuraSpace.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final int columns = constraints.maxWidth >= 1000
                      ? 3
                      : constraints.maxWidth >= 640
                          ? 2
                          : 1;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: columns,
                    mainAxisExtent: 236,
                    crossAxisSpacing: AuraSpace.md,
                    mainAxisSpacing: AuraSpace.md,
                    children: <Widget>[
                      for (final IntegrationDefinition definition
                          in definitions)
                        _IntegrationCard(
                          definition: definition,
                          status: statuses[definition.service]!,
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AuraSpace.lg),
              const _SecurityCard(),
            ],
          ),
        ),
      ),
    );
  }
}

class _IntegrationCard extends StatelessWidget {
  const _IntegrationCard({required this.definition, required this.status});

  final IntegrationDefinition definition;
  final IntegrationStatus status;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color stateColor = _stateColor(status.state);

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_iconFor(definition.iconName),
                  size: 20, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text(definition.label, style: text.titleMedium),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            definition.summary,
            style: text.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AuraSpace.sm),
          StatusPill(
            label: _stateLabel(status.state),
            color: stateColor,
            showDot: false,
            dense: true,
          ),
          const SizedBox(height: AuraSpace.xs),
          Wrap(
            spacing: AuraSpace.xxs,
            children: <Widget>[
              for (final String scope in definition.scopes)
                Chip(
                  label: Text(scope, style: text.labelSmall),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  side: BorderSide(color: AuraColors.border),
                  backgroundColor: AuraColors.backgroundDeep,
                ),
            ],
          ),
          const Spacer(),
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: 'No adapter has been implemented for this service yet.',
              child: OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.link_off_rounded, size: 15),
                label: const Text('Not connected'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _stateLabel(IntegrationConnectionState state) {
    switch (state) {
      case IntegrationConnectionState.disconnected:
        return 'DISCONNECTED';
      case IntegrationConnectionState.unavailable:
        return 'UNAVAILABLE';
      case IntegrationConnectionState.error:
        return 'ERROR';
    }
  }

  Color _stateColor(IntegrationConnectionState state) {
    switch (state) {
      case IntegrationConnectionState.disconnected:
        return AuraColors.textSecondary;
      case IntegrationConnectionState.unavailable:
        return AuraColors.warning;
      case IntegrationConnectionState.error:
        return AuraColors.danger;
    }
  }

  IconData _iconFor(String name) {
    switch (name) {
      case 'mail':
        return Icons.mail_outline_rounded;
      case 'music':
        return Icons.music_note_outlined;
      case 'code':
        return Icons.code_outlined;
      case 'calendar':
        return Icons.calendar_month_outlined;
      case 'cloud':
        return Icons.cloud_outlined;
      case 'research':
        return Icons.travel_explore_outlined;
      default:
        return Icons.extension_outlined;
    }
  }
}

class _SecurityCard extends StatelessWidget {
  const _SecurityCard();

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
              Icon(Icons.key_outlined, size: 20, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Text('Credential boundary', style: text.titleSmall),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'OAuth client secrets and API keys must never be embedded in Flutter '
            'source, settings files, logs or diagnostics exports. A future '
            'adapter must use an OS-backed token store or a secure backend, '
            'scoped per workspace, with explicit connection and disconnection '
            'controls and readable permission lists.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
