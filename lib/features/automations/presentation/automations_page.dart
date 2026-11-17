import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class AutomationsPage extends StatelessWidget {
  const AutomationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlannedModulePage(
      eyebrow: 'Workspace',
      title: 'Automations',
      description:
          'Build simple rules that connect time, device state and integration events to useful actions.',
      phase: 'Phase 4',
      icon: Icons.bolt_outlined,
      accent: AuraColors.warning,
      capabilities: <PlannedCapability>[
        PlannedCapability(
          title: 'Time triggers',
          description: 'Run at a set time, on a schedule or after a delay.',
          icon: Icons.schedule_outlined,
        ),
        PlannedCapability(
          title: 'Device triggers',
          description: 'React when a device connects, disconnects or updates.',
          icon: Icons.devices_outlined,
        ),
        PlannedCapability(
          title: 'Integration triggers',
          description: 'Start flows from mail, code or research events.',
          icon: Icons.extension_outlined,
        ),
        PlannedCapability(
          title: 'Actions',
          description:
              'Notify, refresh the dashboard or trigger device actions.',
          icon: Icons.play_arrow_outlined,
        ),
        PlannedCapability(
          title: 'Family announcements',
          description: 'Send household notices to the shared workspace.',
          icon: Icons.campaign_outlined,
        ),
        PlannedCapability(
          title: 'History',
          description: 'Inspect past runs, status and failures.',
          icon: Icons.history_toggle_off_outlined,
        ),
      ],
      noteTitle: 'Explicit confirmation',
      noteBody:
          'Destructive or sensitive actions will always ask for confirmation before they can run or be enabled.',
    );
  }
}
