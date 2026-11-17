import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class DevicesPage extends StatelessWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlannedModulePage(
      eyebrow: 'Operations',
      title: 'Devices',
      description:
          'A single place to register, inspect and manage every AURA desk companion in your workspace.',
      phase: 'Phase 2',
      icon: Icons.devices_other_outlined,
      accent: AuraColors.primary,
      capabilities: <PlannedCapability>[
        PlannedCapability(
          title: 'Discovery',
          description: 'Find AURA devices on the local network or over BLE.',
          icon: Icons.radar_outlined,
        ),
        PlannedCapability(
          title: 'Registration',
          description: 'Register a device with an identity and friendly name.',
          icon: Icons.app_registration_outlined,
        ),
        PlannedCapability(
          title: 'Connection states',
          description:
              'Show online, offline and connecting states with quality.',
          icon: Icons.network_check_outlined,
        ),
        PlannedCapability(
          title: 'Battery reporting',
          description: 'Display battery level only when the device reports it.',
          icon: Icons.battery_charging_full_outlined,
        ),
        PlannedCapability(
          title: 'Configuration',
          description: 'Rename devices and inspect firmware and sync history.',
          icon: Icons.tune_outlined,
        ),
        PlannedCapability(
          title: 'Safe removal',
          description: 'Remove a device after an explicit confirmation.',
          icon: Icons.delete_outline_rounded,
        ),
      ],
      noteTitle: 'No fake pairing',
      noteBody:
          'BLE and Wi-Fi pairing will only appear once real device communication exists. This screen never simulates a successful connection to hardware.',
    );
  }
}
