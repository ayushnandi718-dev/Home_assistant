import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest device screen: no ESP32 has been paired, so this shows the real
/// empty state and what is required before devices can appear.
class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AuraDevice>> devices = ref.watch(devicesProvider);
    final TextTheme text = Theme.of(context).textTheme;
    final int count = devices.valueOrNull?.length ?? 0;

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
                eyebrow: 'Operations',
                title: 'Devices',
                description:
                    'A single place to register, inspect and manage AURA desk '
                    'companions once device communication exists.',
                icon: Icons.devices_other_outlined,
                trailing: OutlinedButton.icon(
                  onPressed: () => ref.invalidate(devicesProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Check again'),
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              InfoBanner(
                title: count == 0
                    ? 'No AURA devices connected'
                    : '$count device${count == 1 ? '' : 's'} found',
                message: count == 0
                    ? 'The local telemetry API measures this Windows PC; it does '
                        'not mean an AURA device is linked. Pairing requires real '
                        'ESP32 firmware and a device backend, which are not part '
                        'of this foundation build.'
                    : 'Devices reported by the device repository.',
                icon: count == 0
                    ? Icons.link_off_outlined
                    : Icons.devices_rounded,
                tone: count == 0 ? AuraBannerTone.warning : AuraBannerTone.info,
                trailing: StatusPill(
                  label: count == 0 ? 'CORE NOT LINKED' : 'DEVICES FOUND',
                  color: count == 0 ? AuraColors.warning : AuraColors.success,
                  dense: true,
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.radar_outlined, color: AuraColors.primary),
                        const SizedBox(width: AuraSpace.sm),
                        Text('Discovery status', style: text.titleLarge),
                      ],
                    ),
                    const SizedBox(height: AuraSpace.md),
                    _StatusRow(
                      label: 'AURA Core link',
                      value: 'Not linked',
                      color: AuraColors.warning,
                    ),
                    _StatusRow(
                      label: 'BLE / Wi-Fi discovery',
                      value: devices.isLoading ? 'Checking...' : 'Unavailable',
                      color: AuraColors.textSecondary,
                    ),
                    _StatusRow(
                      label: 'Device repository',
                      value: 'Local (no backend)',
                      color: AuraColors.textSecondary,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('What is needed before devices can appear',
                        style: text.titleLarge),
                    const SizedBox(height: AuraSpace.md),
                    _SetupStep(
                      number: '1',
                      title: 'AURA ESP32-S3 hardware',
                      detail: '${AppInfo.hardware} with pairing firmware.',
                    ),
                    _SetupStep(
                      number: '2',
                      title: 'Device communication service',
                      detail: 'A real BLE or Wi-Fi transport and pairing flow.',
                    ),
                    _SetupStep(
                      number: '3',
                      title: 'Authenticated backend',
                      detail:
                          'Device identity, ownership and sync state, with PIN and OAuth handled securely.',
                    ),
                    const SizedBox(height: AuraSpace.md),
                    Text(
                      'This screen never simulates a successful pairing or a '
                      'connected device.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          Text(value, style: text.labelMedium?.copyWith(color: color)),
        ],
      ),
    );
  }
}

class _SetupStep extends StatelessWidget {
  const _SetupStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 14,
            backgroundColor: AuraColors.primary.withValues(alpha: 0.12),
            child: Text(
              number,
              style: text.labelMedium?.copyWith(color: AuraColors.primary),
            ),
          ),
          const SizedBox(width: AuraSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: text.titleSmall),
                const SizedBox(height: AuraSpace.xxs),
                Text(detail, style: text.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
