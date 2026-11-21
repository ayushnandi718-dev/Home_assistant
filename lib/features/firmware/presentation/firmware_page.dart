import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/firmware/domain/firmware_update_preferences.dart';
import 'package:aura_hub/features/firmware/presentation/firmware_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/capability_status_key.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Firmware update workspace.
///
/// This page never downloads, verifies against a signed manifest, or installs
/// firmware. There is no device transport and no release service in this build,
/// so every device-facing state is reported as unavailable. The only real
/// actions here are editing locally saved preferences and computing a SHA-256
/// digest of a file already on this computer.
class FirmwarePage extends ConsumerWidget {
  const FirmwarePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final FirmwareUpdatePreferences preferences =
        ref.watch(firmwareUpdatePreferencesProvider);
    final FirmwareUpdatePreferencesController controller =
        ref.read(activeFirmwareUpdatePreferencesControllerProvider);
    final AuraProfile profile = ref.watch(activeProfileProvider);
    final FirmwareFileReader readFile = ref.watch(firmwareFileReaderProvider);

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
                eyebrow: 'System',
                title: 'Firmware & Updates',
                description: 'Prepare the update settings the AURA panel will '
                    'use once a real device transport and signed release service '
                    'exist. These choices are saved for the ${profile.label} '
                    'workspace.',
                icon: Icons.system_update_outlined,
                accent: AuraColors.secondary,
                trailing: const StatusPill(
                  label: 'Configuration only',
                  color: AuraColors.secondary,
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'No device connected — no update can run',
                message:
                    'This build has neither an AURA transport nor a release '
                    'service. No firmware was downloaded, verified against a '
                    'trusted manifest, or installed. Nothing here sends a command '
                    'to hardware.',
                icon: Icons.info_outline_rounded,
                tone: AuraBannerTone.warning,
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
                      _UpdatePreferencesCard(
                        preferences: preferences,
                        controller: controller,
                      ),
                      const SizedBox(height: AuraSpace.lg),
                      const _ReadinessCard(),
                      const SizedBox(height: AuraSpace.lg),
                      _LocalDigestCard(readFile: readFile),
                    ],
                  );
                  final Widget status = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const <Widget>[
                      _ReleaseStatusCard(),
                      SizedBox(height: AuraSpace.lg),
                      _RecoveryCard(),
                    ],
                  );

                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: controls),
                        const SizedBox(width: AuraSpace.lg),
                        SizedBox(width: 380, child: status),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      status,
                      const SizedBox(height: AuraSpace.lg),
                      controls,
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdatePreferencesCard extends StatelessWidget {
  const _UpdatePreferencesCard({
    required this.preferences,
    required this.controller,
  });

  final FirmwareUpdatePreferences preferences;
  final FirmwareUpdatePreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      accent: AuraColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.tune_rounded, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text('Update preferences', style: text.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Saved on this PC only. These settings describe what a future OTA '
            'service should do; they do not start a check or an install.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          Text('Release channel (saved locally)', style: text.titleSmall),
          const SizedBox(height: AuraSpace.xs),
          SegmentedButton<FirmwareChannel>(
            segments: <ButtonSegment<FirmwareChannel>>[
              for (final FirmwareChannel channel in FirmwareChannel.values)
                ButtonSegment<FirmwareChannel>(
                  value: channel,
                  label: Text(channel.label),
                ),
            ],
            selected: <FirmwareChannel>{preferences.channel},
            onSelectionChanged: (Set<FirmwareChannel> values) {
              if (values.isEmpty) return;
              controller.update(preferences.copyWith(channel: values.first));
            },
          ),
          const SizedBox(height: AuraSpace.xs),
          Text(
            preferences.channel.description,
            style: text.bodySmall?.copyWith(color: AuraColors.textSecondary),
          ),
          const SizedBox(height: AuraSpace.sm),
          SwitchListTile(
            value: preferences.autoCheckEnabled,
            onChanged: (bool value) => controller.update(
              preferences.copyWith(autoCheckEnabled: value),
            ),
            title: const Text('Check for releases automatically'),
            subtitle: const Text('Preference only — no check is performed.'),
          ),
          SwitchListTile(
            value: preferences.requireVerification,
            onChanged: (bool value) => controller.update(
              preferences.copyWith(requireVerification: value),
            ),
            title: const Text('Require verification before install'),
            subtitle: const Text(
              'Applies only when a signed release service exists.',
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final bool stacked =
                  constraints.maxWidth < AuraBreakpoints.mobile;
              const StatusPill pill = StatusPill(
                label: 'Requires AURA hardware to apply',
                color: AuraColors.warning,
                dense: true,
                showDot: false,
              );
              final Widget saveState =
                  ValueListenableBuilder<FirmwareSaveState>(
                valueListenable: controller.saveState,
                builder: (BuildContext context, FirmwareSaveState state,
                    Widget? child) {
                  return Text(
                    state.label,
                    textAlign: stacked ? TextAlign.start : TextAlign.end,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: text.bodySmall?.copyWith(
                      color: state == FirmwareSaveState.failed
                          ? AuraColors.danger
                          : AuraColors.textSecondary,
                    ),
                  );
                },
              );
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    pill,
                    const SizedBox(height: AuraSpace.xs),
                    saveState,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  pill,
                  const SizedBox(width: AuraSpace.sm),
                  Expanded(child: saveState),
                ],
              );
            },
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: controller.reset,
              icon: const Icon(Icons.restore_rounded),
              label: const Text('Reset saved firmware preferences'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard();

  static const List<(IconData, String, String, String, Color)> _items =
      <(IconData, String, String, String, Color)>[
    (
      Icons.bluetooth_rounded,
      'Device transport',
      'A real BLE or Wi-Fi link to an AURA panel.',
      'Requires AURA hardware',
      AuraColors.warning,
    ),
    (
      Icons.cloud_off_outlined,
      'Release service',
      'An authenticated service publishing signed manifests.',
      'Not implemented',
      AuraColors.textSecondary,
    ),
    (
      Icons.verified_outlined,
      'Integrity check',
      'Digest matched against a trusted signed manifest.',
      'Not implemented',
      AuraColors.textSecondary,
    ),
    (
      Icons.system_update_alt_outlined,
      'OTA transfer',
      'Resumable delivery with real device-reported progress.',
      'Not implemented',
      AuraColors.textSecondary,
    ),
    (
      Icons.health_and_safety_outlined,
      'Recovery path',
      'Rollback guidance for an interrupted install.',
      'Not implemented',
      AuraColors.textSecondary,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      accent: AuraColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.checklist_rounded, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: Text('Update readiness', style: text.titleLarge)),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'What a real update needs before this page can report progress. '
            'None of these steps exists in this build.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          for (final (
                IconData icon,
                String title,
                String detail,
                String status,
                Color color
              ) in _items)
            Padding(
              padding: const EdgeInsets.only(bottom: AuraSpace.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(icon, size: 20, color: color),
                  const SizedBox(width: AuraSpace.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: text.titleSmall),
                        const SizedBox(height: 2),
                        Text(
                          detail,
                          style: text.bodySmall
                              ?.copyWith(color: AuraColors.textSecondary),
                        ),
                        const SizedBox(height: AuraSpace.xs),
                        StatusPill(
                          label: status,
                          color: color,
                          dense: true,
                          showDot: false,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _LocalDigestCard extends StatefulWidget {
  const _LocalDigestCard({required this.readFile});

  final FirmwareFileReader readFile;

  @override
  State<_LocalDigestCard> createState() => _LocalDigestCardState();
}

class _LocalDigestCardState extends State<_LocalDigestCard> {
  final TextEditingController _pathController = TextEditingController();
  String? _digest;
  String? _error;
  bool _computing = false;

  @override
  void dispose() {
    _pathController.dispose();
    super.dispose();
  }

  Future<void> _compute() async {
    final String path = _pathController.text.trim();
    if (path.isEmpty) {
      setState(() {
        _digest = null;
        _error = 'Enter a local file path first.';
      });
      return;
    }

    setState(() {
      _computing = true;
      _digest = null;
      _error = null;
    });

    try {
      // A missing or unreadable file throws and is reported by the same catch.
      final List<int> bytes = await widget.readFile(path);
      final Digest result = sha256.convert(bytes);
      if (!mounted) return;
      setState(() {
        _digest = result.toString();
        _computing = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not read that file. Check the path and try again.';
        _computing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      accent: AuraColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.fingerprint_rounded,
                  color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                  child: Text('Local file digest', style: text.titleLarge)),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Compute a SHA-256 of a file already on this computer. This is a '
            'local digest only — it is not integrity or authenticity '
            'verification without a trusted signed manifest.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          TextField(
            controller: _pathController,
            decoration: const InputDecoration(
              labelText: 'Local file path',
              hintText: r'C:\path\to\firmware.bin',
              prefixIcon: Icon(Icons.folder_open_outlined),
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          FilledButton.icon(
            onPressed: _computing ? null : _compute,
            icon: const Icon(Icons.calculate_outlined),
            label: Text(_computing ? 'Computing…' : 'Compute local SHA-256'),
          ),
          if (_digest != null) ...<Widget>[
            const SizedBox(height: AuraSpace.md),
            SelectableText(
              _digest!,
              style: text.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: AuraColors.success,
              ),
            ),
          ],
          if (_error != null) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            Text(
              _error!,
              style: text.bodySmall?.copyWith(color: AuraColors.danger),
            ),
          ],
          const SizedBox(height: AuraSpace.md),
          const StatusPill(
            label: 'Available on this computer',
            color: AuraColors.success,
            dense: true,
            showDot: false,
          ),
        ],
      ),
    );
  }
}

class _ReleaseStatusCard extends StatelessWidget {
  const _ReleaseStatusCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      accent: AuraColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.info_outline_rounded,
                  color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: Text('Release status', style: text.titleLarge)),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          const StatusPill(
            label: 'Not implemented',
            dense: true,
            showDot: false,
          ),
          const SizedBox(height: AuraSpace.md),
          const _StatusRow(
            label: 'Device firmware',
            value: 'Unavailable — no device connected',
          ),
          const _StatusRow(
            label: 'Available release',
            value: 'Unavailable — no release service',
          ),
          const _StatusRow(
            label: 'Update progress',
            value: 'No update in progress',
          ),
          const _StatusRow(
            label: 'Last install',
            value: 'No install recorded in this build',
          ),
          const Divider(height: AuraSpace.lg),
          _StatusRow(
            label: 'App version',
            value: '${AppInfo.version}+${AppInfo.buildNumber}',
          ),
          const _StatusRow(label: 'Stage', value: AppInfo.phase),
          const _StatusRow(label: 'Target hardware', value: AppInfo.hardware),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'The app version above describes AURA Hub, not device firmware.',
            style: text.bodySmall?.copyWith(color: AuraColors.textSecondary),
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
      padding: const EdgeInsets.only(bottom: AuraSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(label, style: text.labelMedium),
          const SizedBox(height: 2),
          Text(
            value,
            style: text.bodyMedium?.copyWith(color: AuraColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _RecoveryCard extends StatelessWidget {
  const _RecoveryCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      accent: AuraColors.secondary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.health_and_safety_outlined,
                  color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text('Recovery & verification', style: text.titleLarge),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Real recovery needs a transport that reports bootloader state and '
            'a signed manifest to verify against. This app cannot reboot a '
            'device, restore an interrupted install, or confirm authenticity.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          const StatusPill(
            label: 'Not implemented',
            dense: true,
            showDot: false,
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'If an update is interrupted on real hardware, follow the vendor '
            'recovery procedure. No firmware is installed by this build.',
            style: text.bodySmall?.copyWith(color: AuraColors.textSecondary),
          ),
        ],
      ),
    );
  }
}
