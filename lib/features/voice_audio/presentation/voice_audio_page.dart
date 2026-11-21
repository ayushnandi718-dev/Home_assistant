import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/voice_audio/domain/microphone_probe.dart';
import 'package:aura_hub/features/voice_audio/domain/voice_preferences.dart';
import 'package:aura_hub/features/voice_audio/presentation/voice_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/capability_status_key.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Below this width a trailing control is stacked under its label instead of
/// squeezing it, matching the responsive rows in Settings and Display Studio.
const double _kStackBreakpoint = 620;

/// Software-side Voice & Audio workspace.
///
/// Preferences are persisted per profile and shown in a local status panel. No
/// microphone is opened, no wake word is detected and no audio is played: those
/// paths require a real speech/audio pipeline and AURA hardware.
class VoiceAudioPage extends ConsumerWidget {
  const VoiceAudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final VoicePreferences preferences = ref.watch(voicePreferencesProvider);
    final VoicePreferencesController controller =
        ref.read(activeVoicePreferencesControllerProvider);
    final AuraProfile profile = ref.watch(activeProfileProvider);
    final AsyncValue<MicrophoneStatus> microphone =
        ref.watch(microphoneStatusProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return AuraScrollArea(
      padding: EdgeInsets.fromLTRB(
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.lg,
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageHeader(
                eyebrow: 'Experience',
                title: 'Voice & Audio',
                description: 'Configure the “Hey AURA” wake phrase, languages, '
                    'listening feedback and audio output for the '
                    '${profile.label} workspace.',
                icon: Icons.graphic_eq_outlined,
                accent: AuraColors.secondary,
                trailing: const StatusPill(
                  label: 'Configuration only',
                  color: AuraColors.secondary,
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'No microphone or speaker path is active',
                message: 'This build has no speech recognition, wake-word '
                    'detection or audio playback pipeline. The switches below '
                    'save intent and drive a local status preview only. No audio '
                    'is captured, played or sent anywhere.',
                icon: Icons.privacy_tip_outlined,
                tone: AuraBannerTone.privacy,
              ),
              const SizedBox(height: AuraSpace.md),
              const CapabilityStatusKey(),
              const SizedBox(height: AuraSpace.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 1040;
                  final Widget controls = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _WakeMicrophoneCard(
                        preferences: preferences,
                        controller: controller,
                        microphone: microphone,
                      ),
                      const SizedBox(height: AuraSpace.lg),
                      _LanguageCard(
                        preferences: preferences,
                        controller: controller,
                      ),
                      const SizedBox(height: AuraSpace.lg),
                      _ResponsesCard(
                        preferences: preferences,
                        controller: controller,
                      ),
                      const SizedBox(height: AuraSpace.lg),
                      _OutputCard(
                        preferences: preferences,
                        controller: controller,
                      ),
                    ],
                  );
                  final Widget statusPanel = _VoiceStatusPanel(
                    preferences: preferences,
                    microphone: microphone,
                    controller: controller,
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: controls),
                        const SizedBox(width: AuraSpace.lg),
                        SizedBox(width: 380, child: statusPanel),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      statusPanel,
                      const SizedBox(height: AuraSpace.lg),
                      controls,
                    ],
                  );
                },
              ),
              const SizedBox(height: AuraSpace.md),
              Text(
                'Preferences are stored on this PC and are isolated per workspace.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WakeMicrophoneCard extends StatelessWidget {
  const _WakeMicrophoneCard({
    required this.preferences,
    required this.controller,
    required this.microphone,
  });

  final VoicePreferences preferences;
  final VoicePreferencesController controller;
  final AsyncValue<MicrophoneStatus> microphone;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.record_voice_over_outlined,
                  color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                  child:
                      Text('Wake phrase & microphone', style: text.titleLarge)),
              const StatusPill(
                label: 'Not implemented',
                color: AuraColors.textSecondary,
                dense: true,
                showDot: false,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            '“${VoicePreferences.wakePhrase}” is the configured phrase. '
            'Saving the switches does not start continuous listening or open a '
            'microphone.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.record_voice_over_outlined),
            title: const Text('Enable wake phrase preference'),
            subtitle:
                const Text('Configuration only — no detector is running.'),
            value: preferences.wakePhraseEnabled,
            onChanged: (bool value) => controller.update(
              preferences.copyWith(wakePhraseEnabled: value),
            ),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.mic_none_outlined),
            title: const Text('Enable microphone preference'),
            subtitle: Text(
              preferences.microphoneEnabled
                  ? 'Enabled in AURA. No permission requested, no audio captured.'
                  : 'Disabled in AURA. No permission requested, no audio captured.',
            ),
            value: preferences.microphoneEnabled,
            onChanged: (bool value) => controller.update(
              preferences.copyWith(microphoneEnabled: value),
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          microphone.when(
            data: (MicrophoneStatus status) => InfoBanner(
              title: status.captureSupported
                  ? 'Microphone path available'
                  : 'Microphone cannot be queried in this build',
              message: '${status.message} OS permission: '
                  '${status.permissionLabel}. Input device: '
                  '${status.deviceLabel}.',
              icon: Icons.privacy_tip_outlined,
              tone: AuraBannerTone.privacy,
            ),
            loading: () => const InfoBanner(
              title: 'Checking microphone capability',
              message: 'Reading the local capability probe…',
              icon: Icons.hourglass_top_rounded,
            ),
            error: (Object error, StackTrace stack) => const InfoBanner(
              title: 'Microphone capability unavailable',
              message: 'The local probe could not be read. No audio path was '
                  'opened and no permission was requested.',
              icon: Icons.error_outline_rounded,
              tone: AuraBannerTone.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageCard extends StatelessWidget {
  const _LanguageCard({
    required this.preferences,
    required this.controller,
  });

  final VoicePreferences preferences;
  final VoicePreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.translate_outlined, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Text('Languages', style: text.titleLarge),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Select the language a future speech pipeline should use. This '
            'preference is saved with the active workspace.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<VoiceLanguage>(
              segments: <ButtonSegment<VoiceLanguage>>[
                for (final VoiceLanguage language in VoiceLanguage.values)
                  ButtonSegment<VoiceLanguage>(
                    value: language,
                    label: Text(language.label),
                  ),
              ],
              selected: <VoiceLanguage>{preferences.language},
              onSelectionChanged: (Set<VoiceLanguage> values) {
                if (values.isEmpty) return;
                controller.update(
                  preferences.copyWith(language: values.first),
                );
              },
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          Wrap(
            spacing: AuraSpace.xs,
            children: const <Widget>[
              Chip(
                avatar: Icon(Icons.lock_outline, size: 15),
                label: Text('Automatic detection — not supported'),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Automatic language detection is not offered: no speech recognition '
            'pipeline exists in this build to support it.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ResponsesCard extends StatelessWidget {
  const _ResponsesCard({
    required this.preferences,
    required this.controller,
  });

  final VoicePreferences preferences;
  final VoicePreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.chat_bubble_outline_rounded,
                  color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text(
                  'Voice responses',
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Set how future spoken replies would sound. The sample below is '
            'text drawn by Flutter, not generated audio.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          _SettingRow(
            icon: Icons.format_list_bulleted_outlined,
            title: 'Response verbosity',
            subtitle: 'How much a reply would say.',
            control: (bool stacked) => DropdownButton<VoiceVerbosity>(
              isExpanded: true,
              isDense: true,
              value: preferences.verbosity,
              items: <DropdownMenuItem<VoiceVerbosity>>[
                for (final VoiceVerbosity value in VoiceVerbosity.values)
                  DropdownMenuItem<VoiceVerbosity>(
                    value: value,
                    child: Text(value.label),
                  ),
              ],
              onChanged: (VoiceVerbosity? value) {
                if (value != null) {
                  controller.update(preferences.copyWith(verbosity: value));
                }
              },
            ),
          ),
          _SettingRow(
            icon: Icons.speed_outlined,
            title: 'Response speed',
            subtitle: 'Stored rate for future speech synthesis.',
            control: (bool stacked) => DropdownButton<VoiceSpeed>(
              isExpanded: true,
              isDense: true,
              value: preferences.speed,
              items: <DropdownMenuItem<VoiceSpeed>>[
                for (final VoiceSpeed value in VoiceSpeed.values)
                  DropdownMenuItem<VoiceSpeed>(
                    value: value,
                    child: Text(value.label),
                  ),
              ],
              onChanged: (VoiceSpeed? value) {
                if (value != null) {
                  controller.update(preferences.copyWith(speed: value));
                }
              },
            ),
          ),
          _SettingRow(
            icon: Icons.radio_button_checked_outlined,
            title: 'Confirmation style',
            subtitle: 'Spoken confirmation needs AURA hardware.',
            inlineControlWidth: 180,
            control: (bool stacked) => DropdownButton<VoiceConfirmation>(
              isExpanded: true,
              isDense: true,
              value: preferences.confirmation,
              items: <DropdownMenuItem<VoiceConfirmation>>[
                for (final VoiceConfirmation value in VoiceConfirmation.values)
                  DropdownMenuItem<VoiceConfirmation>(
                    value: value,
                    child: Text(value.label),
                  ),
              ],
              onChanged: (VoiceConfirmation? value) {
                if (value != null) {
                  controller.update(preferences.copyWith(confirmation: value));
                }
              },
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AuraSpace.md),
            decoration: BoxDecoration(
              color: AuraColors.card.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(AuraRadius.control),
              border:
                  Border.all(color: AuraColors.border.withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Sample response', style: text.labelMedium),
                const SizedBox(height: AuraSpace.xs),
                Text(preferences.responsePreview, style: text.bodyMedium),
                const SizedBox(height: AuraSpace.xxs),
                Text(
                  '${preferences.language.label}  ·  '
                  '${preferences.speed.label} (${preferences.speed.rate}×)',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          const _FeedbackPreview(),
        ],
      ),
    );
  }
}

class _OutputCard extends StatelessWidget {
  const _OutputCard({
    required this.preferences,
    required this.controller,
  });

  final VoicePreferences preferences;
  final VoicePreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.volume_up_outlined, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text(
                  'Output & volume',
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'No output path is wired up in this build. The target and level are '
            'saved as configuration and shown in the local preview only.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          _SettingRow(
            icon: Icons.speaker_outlined,
            title: 'Output target',
            subtitle: 'Configuration only — no audio is routed.',
            inlineControlWidth: 170,
            control: (bool stacked) => DropdownButton<AudioOutputPreference>(
              isExpanded: true,
              isDense: true,
              value: preferences.output,
              items: <DropdownMenuItem<AudioOutputPreference>>[
                for (final AudioOutputPreference value
                    in AudioOutputPreference.values)
                  DropdownMenuItem<AudioOutputPreference>(
                    value: value,
                    child: Text(switch (value) {
                      AudioOutputPreference.computerSpeakers => 'This computer',
                      AudioOutputPreference.auraPanel =>
                        'AURA panel (hardware)',
                    }),
                  ),
              ],
              onChanged: (AudioOutputPreference? value) {
                if (value != null) {
                  controller.update(preferences.copyWith(output: value));
                }
              },
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          Row(
            children: <Widget>[
              const Icon(Icons.volume_down_outlined, size: 18),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Slider(
                  value: preferences.volume.toDouble(),
                  min: VoicePreferences.minVolume.toDouble(),
                  max: VoicePreferences.maxVolume.toDouble(),
                  divisions: 20,
                  label: '${preferences.volume}%',
                  onChanged: (double value) => controller.update(
                    preferences.copyWith(volume: value.round()),
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '${preferences.volume}%',
                  textAlign: TextAlign.end,
                  style: text.labelLarge,
                ),
              ),
            ],
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(AuraRadius.pill),
            child: LinearProgressIndicator(
              value: preferences.volume / VoicePreferences.maxVolume,
              minHeight: 6,
              color: AuraColors.secondary,
              backgroundColor: AuraColors.border.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: AuraSpace.xs),
          Text(
            'The bar previews the saved level. It does not change Windows system '
            'volume or play any sound.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AuraSpace.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const StatusPill pill = StatusPill(
                label: 'Requires AURA hardware',
                color: AuraColors.warning,
                dense: true,
                showDot: false,
              );
              final Widget scanButton = OutlinedButton.icon(
                onPressed: null,
                icon: const Icon(Icons.bluetooth_audio_outlined, size: 16),
                label: const Text('Scan for Bluetooth speakers'),
              );
              if (constraints.maxWidth < _kStackBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(width: double.infinity, child: scanButton),
                    const SizedBox(height: AuraSpace.xs),
                    pill,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Expanded(child: scanButton),
                  const SizedBox(width: AuraSpace.sm),
                  pill,
                ],
              );
            },
          ),
          const SizedBox(height: AuraSpace.sm),
          const InfoBanner(
            title: 'Bluetooth audio is not claimed',
            message: 'The ESP32-S3 target does not natively transmit Bluetooth '
                'Classic A2DP audio. No scan, pairing or speaker output is '
                'implemented, and no device is simulated.',
            icon: Icons.info_outline_rounded,
            tone: AuraBannerTone.warning,
          ),
          const SizedBox(height: AuraSpace.md),
          Align(
            alignment: Alignment.centerLeft,
            child: ValueListenableBuilder<VoiceSaveState>(
              valueListenable: controller.saveState,
              builder: (BuildContext context, VoiceSaveState state, _) {
                return Wrap(
                  spacing: AuraSpace.sm,
                  runSpacing: AuraSpace.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Text(
                      state.label,
                      style: text.bodySmall?.copyWith(
                        color: state == VoiceSaveState.failed
                            ? AuraColors.danger
                            : AuraColors.textSecondary,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => controller.reset(),
                      icon: const Icon(Icons.restore_rounded, size: 16),
                      label: const Text('Reset workspace voice settings'),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _VoiceStatusPanel extends StatelessWidget {
  const _VoiceStatusPanel({
    required this.preferences,
    required this.microphone,
    required this.controller,
  });

  final VoicePreferences preferences;
  final AsyncValue<MicrophoneStatus> microphone;
  final VoicePreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.graphic_eq_outlined, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: Text('Voice status', style: text.titleLarge)),
              const StatusPill(
                label: 'Preview only',
                color: AuraColors.secondary,
                dense: true,
                showDot: false,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          _StatusRow(
            label: 'Wake phrase',
            value: preferences.wakePhraseEnabled
                ? '“${VoicePreferences.wakePhrase}” enabled'
                : 'Disabled',
          ),
          _StatusRow(
            label: 'Microphone preference',
            value: preferences.microphoneEnabled ? 'Enabled' : 'Disabled',
          ),
          _StatusRow(
            label: 'Listening',
            value: preferences.voiceInputRequested
                ? 'Requested (no detector running)'
                : 'Idle — no capture',
          ),
          _StatusRow(
            label: 'Language',
            value: preferences.language.label,
          ),
          _StatusRow(
            label: 'Confirmation',
            value: preferences.confirmation.label,
          ),
          _StatusRow(
            label: 'Output target',
            value: preferences.output.label,
          ),
          _StatusRow(label: 'Volume', value: '${preferences.volume}%'),
          const SizedBox(height: AuraSpace.sm),
          microphone.when(
            data: (MicrophoneStatus status) => _StatusRow(
              label: 'OS permission',
              value: status.permissionLabel,
            ),
            loading: () => const _StatusRow(
              label: 'OS permission',
              value: 'Checking…',
            ),
            error: (Object error, StackTrace stack) => const _StatusRow(
              label: 'OS permission',
              value: 'Unavailable',
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          Text(
            'This panel reflects saved preferences only. It is not a live '
            'microphone level, a paired-device list or an audio route.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AuraSpace.xs),
          ValueListenableBuilder<VoiceSaveState>(
            valueListenable: controller.saveState,
            builder: (BuildContext context, VoiceSaveState state, _) => Text(
              state.label,
              style: text.bodySmall?.copyWith(
                color: state == VoiceSaveState.failed
                    ? AuraColors.danger
                    : AuraColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeedbackPreview extends StatefulWidget {
  const _FeedbackPreview();

  @override
  State<_FeedbackPreview> createState() => _FeedbackPreviewState();
}

class _FeedbackPreviewState extends State<_FeedbackPreview> {
  int _index = 0;

  ListeningFeedbackState get _current => ListeningFeedbackState.values[_index];

  void _advance() {
    setState(() {
      _index = (_index + 1) % ListeningFeedbackState.values.length;
    });
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AuraSpace.md),
      decoration: BoxDecoration(
        color: AuraColors.card.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(AuraRadius.control),
        border: Border.all(color: AuraColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(_current.icon, size: 18, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.xs),
              Expanded(
                child: Text(
                  'Feedback preview: ${_current.label}',
                  style: text.titleSmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Wrap(
            spacing: AuraSpace.xxs,
            children: <Widget>[
              for (final ListeningFeedbackState state
                  in ListeningFeedbackState.values)
                ChoiceChip(
                  label: Text(state.label),
                  selected: state == _current,
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(
                      () =>
                          _index = ListeningFeedbackState.values.indexOf(state),
                    );
                  },
                ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final Widget previewButton = OutlinedButton.icon(
                onPressed: _advance,
                icon: const Icon(Icons.skip_next_rounded, size: 16),
                label: const Text('Preview next state'),
              );
              final Widget explanation = Text(
                'Visual states only. No transition is driven by real audio.',
                style: text.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              );
              if (constraints.maxWidth < _kStackBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.centerLeft,
                      child: previewButton,
                    ),
                    const SizedBox(height: AuraSpace.xs),
                    explanation,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  Flexible(
                    flex: 2,
                    fit: FlexFit.loose,
                    child: previewButton,
                  ),
                  const SizedBox(width: AuraSpace.sm),
                  Expanded(flex: 3, child: explanation),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodySmall)),
          const SizedBox(width: AuraSpace.sm),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: text.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting row whose control never steals width from its label.
///
/// Below [_kStackBreakpoint] the control is placed on its own line, aligned
/// under the text after the leading icon. Above it the original trailing
/// layout is preserved. Mirrors the responsive pattern in Settings.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.control,
    this.inlineControlWidth = 160,
  });

  static const double _textOffset = 30; // 18px icon + AuraSpace.sm gap.

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function(bool stacked) control;
  final double inlineControlWidth;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xxs),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget label = Row(
            children: <Widget>[
              Icon(icon, size: 18, color: AuraColors.textSecondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < _kStackBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                label,
                Padding(
                  padding: const EdgeInsets.only(
                    left: _textOffset,
                    top: AuraSpace.xs,
                  ),
                  child: control(true),
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: label),
              const SizedBox(width: AuraSpace.sm),
              SizedBox(
                width: inlineControlWidth,
                child: control(false),
              ),
            ],
          );
        },
      ),
    );
  }
}
