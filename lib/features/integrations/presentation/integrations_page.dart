import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class IntegrationsPage extends StatelessWidget {
  const IntegrationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlannedModulePage(
      eyebrow: 'Experience',
      title: 'Integrations',
      description:
          'Connect the services that give AURA context: mail, music, code, weather and research.',
      phase: 'Phase 3',
      icon: Icons.extension_outlined,
      accent: AuraColors.primary,
      capabilities: <PlannedCapability>[
        PlannedCapability(
          title: 'Gmail',
          description: 'Private mail summaries and calendar context.',
          icon: Icons.mail_outline_rounded,
        ),
        PlannedCapability(
          title: 'Spotify',
          description: 'Playback state and household music controls.',
          icon: Icons.music_note_outlined,
        ),
        PlannedCapability(
          title: 'GitHub',
          description: 'Repository activity and pull request updates.',
          icon: Icons.code_outlined,
        ),
        PlannedCapability(
          title: 'Weather',
          description: 'Local conditions for the family dashboard.',
          icon: Icons.cloud_outlined,
        ),
        PlannedCapability(
          title: 'Tavily research',
          description: 'On-demand web research with cited results.',
          icon: Icons.travel_explore_outlined,
        ),
        PlannedCapability(
          title: 'Permissions',
          description: 'Connection state, scopes and disconnect controls.',
          icon: Icons.fact_check_outlined,
        ),
      ],
      noteTitle: 'Secrets stay on the backend',
      noteBody:
          'OAuth credentials and API keys must never be embedded in Flutter source or exposed in logs. Token handling belongs on the Node.js backend.',
    );
  }
}
