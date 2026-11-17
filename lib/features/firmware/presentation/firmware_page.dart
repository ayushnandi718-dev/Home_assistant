import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class FirmwarePage extends StatelessWidget {
  const FirmwarePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlannedModulePage(
      eyebrow: 'System',
      title: 'Firmware & Updates',
      description:
          'Track installed firmware, available releases, update progress and recovery information.',
      phase: 'Phase 4',
      icon: Icons.system_update_outlined,
      accent: AuraColors.secondary,
      capabilities: <PlannedCapability>[
        PlannedCapability(
          title: 'Version overview',
          description: 'Current device version and available release state.',
          icon: Icons.info_outline_rounded,
        ),
        PlannedCapability(
          title: 'Update progress',
          description: 'Real download and install states from the OTA service.',
          icon: Icons.linear_scale_rounded,
        ),
        PlannedCapability(
          title: 'Update history',
          description: 'A dated record of firmware changes per device.',
          icon: Icons.history_outlined,
        ),
        PlannedCapability(
          title: 'Release notes',
          description: 'Explain what changes before any update is accepted.',
          icon: Icons.description_outlined,
        ),
        PlannedCapability(
          title: 'Recovery',
          description: 'Guidance for failed or interrupted updates.',
          icon: Icons.health_and_safety_outlined,
        ),
        PlannedCapability(
          title: 'Verification',
          description: 'Validate firmware integrity before installation.',
          icon: Icons.verified_outlined,
        ),
      ],
      noteTitle: 'No simulated installs',
      noteBody:
          'The OTA architecture will be prepared, but this build never claims that a firmware update succeeded when no real update ran.',
    );
  }
}
