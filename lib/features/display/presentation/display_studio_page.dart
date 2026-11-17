import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class DisplayStudioPage extends StatelessWidget {
  const DisplayStudioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlannedModulePage(
      eyebrow: 'Experience',
      title: 'Display Studio',
      description:
          'Shape what appears on the AURA panel: brightness, widgets, wallpaper and sleep behaviour.',
      phase: 'Phase 3',
      icon: Icons.palette_outlined,
      accent: AuraColors.primary,
      capabilities: <PlannedCapability>[
        PlannedCapability(
          title: 'Brightness & timeout',
          description: 'Level, screen timeout and sleep schedule controls.',
          icon: Icons.brightness_6_outlined,
        ),
        PlannedCapability(
          title: 'Theme & wallpaper',
          description: 'Pick a visual theme and panel wallpaper.',
          icon: Icons.wallpaper_outlined,
        ),
        PlannedCapability(
          title: 'Dashboard widgets',
          description: 'Arrange clock, weather, calendar and status widgets.',
          icon: Icons.widgets_outlined,
        ),
        PlannedCapability(
          title: 'Clock styles',
          description: 'Choose from analog, digital and minimal clocks.',
          icon: Icons.schedule_outlined,
        ),
        PlannedCapability(
          title: 'Orientation',
          description: 'Change orientation on hardware that supports it.',
          icon: Icons.screen_rotation_outlined,
        ),
        PlannedCapability(
          title: 'Local preview',
          description: 'Preview changes locally before device sync exists.',
          icon: Icons.preview_outlined,
        ),
      ],
      noteTitle: 'Preview only',
      noteBody:
          'Until device communication is implemented, controls here will only change a local preview. They will not modify the ESP32 panel.',
    );
  }
}
