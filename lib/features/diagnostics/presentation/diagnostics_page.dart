import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class DiagnosticsPage extends StatelessWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlannedModulePage(
      eyebrow: 'System',
      title: 'Diagnostics & Logs',
      description:
          'Search, filter and inspect structured events across the app, device, backend and security layers.',
      phase: 'Phase 4',
      icon: Icons.monitor_heart_outlined,
      accent: AuraColors.primary,
      capabilities: <PlannedCapability>[
        PlannedCapability(
          title: 'Categories',
          description: 'System, hardware, network, auth, profiles and voice.',
          icon: Icons.category_outlined,
        ),
        PlannedCapability(
          title: 'Severity levels',
          description: 'DEBUG, INFO, WARNING, ERROR and CRITICAL.',
          icon: Icons.priority_high_outlined,
        ),
        PlannedCapability(
          title: 'Search & filters',
          description: 'Find events by keyword, ID, date, category or level.',
          icon: Icons.search_outlined,
        ),
        PlannedCapability(
          title: 'Event inspector',
          description: 'Open an individual event with structured context.',
          icon: Icons.article_outlined,
        ),
        PlannedCapability(
          title: 'Export',
          description: 'Download filtered events as CSV or JSON.',
          icon: Icons.file_download_outlined,
        ),
        PlannedCapability(
          title: 'Retention',
          description: 'Configure automatic retention and safe log clearing.',
          icon: Icons.delete_sweep_outlined,
        ),
      ],
      noteTitle: 'Privacy by default',
      noteBody:
          'PINs, passwords, OAuth tokens, raw microphone recordings and private email content must never be written to logs.',
    );
  }
}
