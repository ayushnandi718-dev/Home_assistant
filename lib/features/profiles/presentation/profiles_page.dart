import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class ProfilesPage extends StatelessWidget {
  const ProfilesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlannedModulePage(
      eyebrow: 'Workspace',
      title: 'Profiles & Security',
      description:
          'Two isolated workspaces: a private Ayush profile and a shared Family profile for the household.',
      phase: 'Phase 2',
      icon: Icons.shield_outlined,
      accent: AuraColors.secondary,
      capabilities: <PlannedCapability>[
        PlannedCapability(
          title: 'Ayush workspace',
          description: 'Private integrations, AI context, tasks and logs.',
          icon: Icons.lock_outline_rounded,
        ),
        PlannedCapability(
          title: 'PIN challenge',
          description: 'Authentication is always required to enter Ayush.',
          icon: Icons.pin_outlined,
        ),
        PlannedCapability(
          title: 'Family workspace',
          description: 'Shared dashboard, weather, calendar and announcements.',
          icon: Icons.family_restroom_outlined,
        ),
        PlannedCapability(
          title: 'Data isolation',
          description: 'Family must never reach private Ayush integrations.',
          icon: Icons.domain_verification_outlined,
        ),
        PlannedCapability(
          title: 'Secure session storage',
          description: 'Sensitive local material goes into secure storage.',
          icon: Icons.key_outlined,
        ),
        PlannedCapability(
          title: 'Switch hygiene',
          description: 'Clear private state and caches when leaving Ayush.',
          icon: Icons.cleaning_services_outlined,
        ),
      ],
      noteTitle: 'Backend enforcement',
      noteBody:
          'The PIN screen is only an interface in this milestone. Final access control must be enforced by the backend; UI visibility alone is never enough.',
    );
  }
}
