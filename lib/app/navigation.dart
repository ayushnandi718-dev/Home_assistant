import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:flutter/material.dart';

enum AuraNavSection { overview, control, system }

class AuraDestination {
  const AuraDestination({
    required this.path,
    required this.label,
    required this.shortLabel,
    required this.icon,
    required this.selectedIcon,
    required this.section,
  });

  final String path;
  final String label;
  final String shortLabel;
  final IconData icon;
  final IconData selectedIcon;
  final AuraNavSection section;
}

const List<AuraDestination> auraDestinations = <AuraDestination>[
  AuraDestination(
    path: AppRoutes.dashboard,
    label: 'Dashboard',
    shortLabel: 'Home',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard_rounded,
    section: AuraNavSection.overview,
  ),
  AuraDestination(
    path: AppRoutes.devices,
    label: 'Devices',
    shortLabel: 'Devices',
    icon: Icons.devices_other_outlined,
    selectedIcon: Icons.devices_other_rounded,
    section: AuraNavSection.overview,
  ),
  AuraDestination(
    path: AppRoutes.profiles,
    label: 'Profiles & Security',
    shortLabel: 'Profiles',
    icon: Icons.shield_outlined,
    selectedIcon: Icons.shield_rounded,
    section: AuraNavSection.control,
  ),
  AuraDestination(
    path: AppRoutes.displayStudio,
    label: 'Display Studio',
    shortLabel: 'Display',
    icon: Icons.palette_outlined,
    selectedIcon: Icons.palette_rounded,
    section: AuraNavSection.control,
  ),
  AuraDestination(
    path: AppRoutes.voiceAudio,
    label: 'Voice & Audio',
    shortLabel: 'Voice',
    icon: Icons.graphic_eq_outlined,
    selectedIcon: Icons.graphic_eq_rounded,
    section: AuraNavSection.control,
  ),
  AuraDestination(
    path: AppRoutes.integrations,
    label: 'Integrations',
    shortLabel: 'Connect',
    icon: Icons.extension_outlined,
    selectedIcon: Icons.extension_rounded,
    section: AuraNavSection.control,
  ),
  AuraDestination(
    path: AppRoutes.ai,
    label: 'AI Assistant',
    shortLabel: 'AI',
    icon: Icons.auto_awesome_outlined,
    selectedIcon: Icons.auto_awesome_rounded,
    section: AuraNavSection.control,
  ),
  AuraDestination(
    path: AppRoutes.automations,
    label: 'Automations',
    shortLabel: 'Automate',
    icon: Icons.bolt_outlined,
    selectedIcon: Icons.bolt_rounded,
    section: AuraNavSection.control,
  ),
  AuraDestination(
    path: AppRoutes.notifications,
    label: 'Notifications',
    shortLabel: 'Alerts',
    icon: Icons.notifications_none_outlined,
    selectedIcon: Icons.notifications_rounded,
    section: AuraNavSection.system,
  ),
  AuraDestination(
    path: AppRoutes.diagnostics,
    label: 'Diagnostics & Logs',
    shortLabel: 'Diagnostics',
    icon: Icons.monitor_heart_outlined,
    selectedIcon: Icons.monitor_heart_rounded,
    section: AuraNavSection.system,
  ),
  AuraDestination(
    path: AppRoutes.firmware,
    label: 'Firmware & Updates',
    shortLabel: 'Firmware',
    icon: Icons.system_update_outlined,
    selectedIcon: Icons.system_update_rounded,
    section: AuraNavSection.system,
  ),
  AuraDestination(
    path: AppRoutes.settings,
    label: 'Settings',
    shortLabel: 'Settings',
    icon: Icons.settings_outlined,
    selectedIcon: Icons.settings_rounded,
    section: AuraNavSection.system,
  ),
];

String sectionLabel(AuraNavSection section) {
  switch (section) {
    case AuraNavSection.overview:
      return 'OVERVIEW';
    case AuraNavSection.control:
      return 'CONTROL';
    case AuraNavSection.system:
      return 'SYSTEM';
  }
}

AuraDestination? destinationForLocation(String location) {
  for (final AuraDestination destination in auraDestinations) {
    if (location == destination.path) return destination;
  }
  return null;
}
