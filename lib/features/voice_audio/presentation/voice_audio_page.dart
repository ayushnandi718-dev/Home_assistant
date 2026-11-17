import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/planned_module_page.dart';
import 'package:flutter/material.dart';

class VoiceAudioPage extends StatelessWidget {
  const VoiceAudioPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const PlannedModulePage(
      eyebrow: 'Experience',
      title: 'Voice & Audio',
      description:
          'Configure the Hey AURA wake phrase, languages, listening feedback and audio output.',
      phase: 'Phase 3',
      icon: Icons.graphic_eq_outlined,
      accent: AuraColors.secondary,
      capabilities: <PlannedCapability>[
        PlannedCapability(
          title: 'Wake phrase',
          description: 'Enable or disable the Hey AURA listening mode.',
          icon: Icons.record_voice_over_outlined,
        ),
        PlannedCapability(
          title: 'Microphone',
          description:
              'Microphone switch, listening indicator and privacy state.',
          icon: Icons.mic_none_outlined,
        ),
        PlannedCapability(
          title: 'Languages',
          description: 'Bengali, Hindi, English and automatic detection.',
          icon: Icons.translate_outlined,
        ),
        PlannedCapability(
          title: 'Voice responses',
          description: 'Response verbosity, speed and confirmation style.',
          icon: Icons.chat_bubble_outline_rounded,
        ),
        PlannedCapability(
          title: 'Output & volume',
          description: 'Select a supported output device and control volume.',
          icon: Icons.volume_up_outlined,
        ),
        PlannedCapability(
          title: 'Bluetooth devices',
          description: 'Manage external speakers through supported hardware.',
          icon: Icons.bluetooth_audio_outlined,
        ),
      ],
      noteTitle: 'Hardware limitation',
      noteBody:
          'The ESP32-S3 does not natively transmit Bluetooth Classic A2DP audio. Interfaces here will reflect supported paths only and will never claim unsupported speaker output works.',
    );
  }
}
