import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return PlannedModulePage(
      eyebrow: 'System',
      title: 'Settings',
      description:
          'Appearance, privacy, notifications and data controls for the AURA Hub experience.',
      phase: 'Phase 5',
      icon: Icons.settings_outlined,
      accent: AuraColors.textSecondary,
      capabilities: const <PlannedCapability>[
        PlannedCapability(
          title: 'Appearance',
          description: 'Theme density and accent preferences.',
          icon: Icons.palette_outlined,
        ),
        PlannedCapability(
          title: 'Notifications',
          description: 'Delivery rules for alerts and announcements.',
          icon: Icons.notifications_none_rounded,
        ),
        PlannedCapability(
          title: 'Privacy',
          description: 'Session lifetime, caches and data minimisation.',
          icon: Icons.privacy_tip_outlined,
        ),
        PlannedCapability(
          title: 'Storage',
          description: 'Local database and retention configuration.',
          icon: Icons.storage_outlined,
        ),
        PlannedCapability(
          title: 'Backend',
          description: 'API and WebSocket endpoints once services are live.',
          icon: Icons.dns_outlined,
        ),
        PlannedCapability(
          title: 'About',
          description:
              '${AppInfo.name} ${AppInfo.version} by ${AppInfo.developer}.',
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }
}
