import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Device lifecycle UI backed by an explicit transport-neutral contract.
class DevicesPage extends ConsumerWidget {
  const DevicesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceDiscoveryState discovery = ref.watch(deviceConnectionProvider);
    final DevicePairingState pairing = ref.watch(devicePairingProvider);
    final DeviceLinkState link = ref.watch(deviceLinkProvider);
    final List<AuraDevice> devices = discovery.devices;
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
                eyebrow: 'Operations',
                title: 'Devices',
                description:
                    'Discover, pair and manage AURA desk companions when a '
                    'device transport is installed.',
                icon: Icons.devices_other_outlined,
                trailing: FilledButton.icon(
                  onPressed: discovery.isDiscovering
                      ? null
                      : () => ref
                          .read(deviceConnectionProvider.notifier)
                          .discover(),
                  icon: discovery.isDiscovering
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.radar_rounded, size: 16),
                  label: Text(
                    discovery.isDiscovering ? 'Discovering' : 'Find devices',
                  ),
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              _DiscoveryBanner(discovery: discovery),
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.radar_outlined, color: AuraColors.primary),
                        const SizedBox(width: AuraSpace.sm),
                        Expanded(
                          child: Text(
                            'Connection status',
                            style: text.titleLarge,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AuraSpace.md),
                    _StatusRow(
                      label: 'AURA device connection',
                      value: _linkLabel(link.status),
                      color: link.isConnected
                          ? AuraColors.success
                          : AuraColors.warning,
                    ),
                    _StatusRow(
                      label: 'BLE / Wi-Fi discovery',
                      value: _discoveryLabel(discovery.status),
                      color: _discoveryColor(discovery.status),
                    ),
                    _StatusRow(
                      label: 'Pairing',
                      value: _pairingLabel(pairing.status),
                      color: _pairingColor(pairing.status),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              if (devices.isNotEmpty)
                _DevicesList(devices: devices, pairing: pairing)
              else
                _TransportSetupCard(message: discovery.message),
            ],
          ),
        ),
      ),
    );
  }
}

class _DiscoveryBanner extends StatelessWidget {
  const _DiscoveryBanner({required this.discovery});

  final DeviceDiscoveryState discovery;

  @override
  Widget build(BuildContext context) {
    final bool unavailable =
        discovery.status == DeviceDiscoveryStatus.unavailable;
    final bool failed = discovery.status == DeviceDiscoveryStatus.error;
    return InfoBanner(
      title: unavailable
          ? 'Device transport unavailable'
          : discovery.isDiscovering
              ? 'Looking for AURA devices'
              : failed
                  ? 'Device discovery could not complete'
                  : discovery.devices.isEmpty
                      ? 'No AURA devices discovered'
                      : '${discovery.devices.length} AURA device${discovery.devices.length == 1 ? '' : 's'} found',
      message: discovery.message ??
          'Windows host telemetry is separate from AURA device discovery. '
              'A successful telemetry API connection never represents a paired device.',
      icon: unavailable || failed
          ? Icons.link_off_outlined
          : discovery.isDiscovering
              ? Icons.radar_rounded
              : Icons.devices_other_outlined,
      tone:
          unavailable || failed ? AuraBannerTone.warning : AuraBannerTone.info,
      trailing: StatusPill(
        label: _discoveryLabel(discovery.status).toUpperCase(),
        color: _discoveryColor(discovery.status),
        dense: true,
      ),
    );
  }
}

class _DevicesList extends ConsumerWidget {
  const _DevicesList({required this.devices, required this.pairing});

  final List<AuraDevice> devices;
  final DevicePairingState pairing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('Discovered devices', style: text.titleLarge),
          const SizedBox(height: AuraSpace.sm),
          for (final AuraDevice device in devices)
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                final bool stacked =
                    constraints.maxWidth < AuraBreakpoints.mobile;
                final Widget pairButton = OutlinedButton(
                  onPressed: pairing.status == DevicePairingStatus.pairing
                      ? null
                      : () => ref
                          .read(devicePairingProvider.notifier)
                          .pair(device.id),
                  child: Text(pairing.status == DevicePairingStatus.pairing
                      ? 'Pairing…'
                      : 'Pair'),
                );
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.memory_rounded),
                  title: Text(device.name),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '${device.model} · ${device.transport.label} · '
                        '${device.connectionState.label} · '
                        'FW ${device.firmwareVersion}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (stacked) ...<Widget>[
                        const SizedBox(height: AuraSpace.xs),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: pairButton,
                        ),
                      ],
                    ],
                  ),
                  trailing: stacked ? null : pairButton,
                );
              },
            ),
          if (pairing.message != null) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            Text(pairing.message!, style: text.bodySmall),
          ],
          const SizedBox(height: AuraSpace.md),
          Text(
            'Pairing uses a state machine only. Wi-Fi passwords and device '
            'secrets are never stored in ordinary app preferences.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _TransportSetupCard extends StatelessWidget {
  const _TransportSetupCard({this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
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
          const _SetupStep(
            number: '2',
            title: 'Device transport',
            detail:
                'A BLE or Wi-Fi adapter that implements discovery and pairing.',
          ),
          const _SetupStep(
            number: '3',
            title: 'Secure ownership service',
            detail: 'Device identity, ownership and sync state.',
          ),
          if (message != null) ...<Widget>[
            const SizedBox(height: AuraSpace.md),
            Text(message!, style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AuraSpace.xs),
        child: Row(children: <Widget>[
          Expanded(
              child:
                  Text(label, style: Theme.of(context).textTheme.bodyMedium)),
          Text(value,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: color)),
        ]),
      );
}

class _SetupStep extends StatelessWidget {
  const _SetupStep(
      {required this.number, required this.title, required this.detail});
  final String number;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: AuraSpace.sm),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              CircleAvatar(
                  radius: 14,
                  backgroundColor: AuraColors.primary.withValues(alpha: 0.12),
                  child: Text(number)),
              const SizedBox(width: AuraSpace.md),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: AuraSpace.xxs),
                    Text(detail, style: Theme.of(context).textTheme.bodySmall),
                  ])),
            ]),
      );
}

String _linkLabel(DeviceLinkStatus status) => switch (status) {
      DeviceLinkStatus.notPaired => 'Not paired',
      DeviceLinkStatus.disconnected => 'Disconnected',
      DeviceLinkStatus.connecting => 'Connecting',
      DeviceLinkStatus.connected => 'Connected',
      DeviceLinkStatus.unavailable => 'Unavailable',
    };

String _discoveryLabel(DeviceDiscoveryStatus status) => switch (status) {
      DeviceDiscoveryStatus.idle => 'Not started',
      DeviceDiscoveryStatus.discovering => 'Discovering',
      DeviceDiscoveryStatus.available => 'Available',
      DeviceDiscoveryStatus.unavailable => 'Unavailable',
      DeviceDiscoveryStatus.error => 'Error',
    };

Color _discoveryColor(DeviceDiscoveryStatus status) => switch (status) {
      DeviceDiscoveryStatus.available => AuraColors.success,
      DeviceDiscoveryStatus.discovering => AuraColors.primary,
      DeviceDiscoveryStatus.unavailable ||
      DeviceDiscoveryStatus.error =>
        AuraColors.warning,
      DeviceDiscoveryStatus.idle => AuraColors.textSecondary,
    };

String _pairingLabel(DevicePairingStatus status) => switch (status) {
      DevicePairingStatus.idle => 'Not started',
      DevicePairingStatus.pairing => 'Pairing',
      DevicePairingStatus.paired => 'Paired',
      DevicePairingStatus.unavailable => 'Unavailable',
      DevicePairingStatus.error => 'Error',
    };

Color _pairingColor(DevicePairingStatus status) => switch (status) {
      DevicePairingStatus.paired => AuraColors.success,
      DevicePairingStatus.pairing => AuraColors.primary,
      DevicePairingStatus.unavailable ||
      DevicePairingStatus.error =>
        AuraColors.warning,
      DevicePairingStatus.idle => AuraColors.textSecondary,
    };
