import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Mobile Home's highest-priority card.
///
/// It only reports device facts that came from the device repository. With no
/// transport installed the repository is empty, so the honest "No panel paired"
/// state is shown instead of a simulated connection.
class MobileDeviceStatusCard extends ConsumerWidget {
  const MobileDeviceStatusCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceLinkState link = ref.watch(deviceLinkProvider);
    final DeviceDiscoveryState discovery = ref.watch(deviceConnectionProvider);
    final DevicePairingState pairing = ref.watch(devicePairingProvider);
    final List<AuraDevice> devices =
        ref.watch(devicesProvider).valueOrNull ?? const <AuraDevice>[];

    AuraDevice? paired;
    if (link.isConnected && link.deviceId != null) {
      for (final AuraDevice device in devices) {
        if (device.id == link.deviceId) {
          paired = device;
          break;
        }
      }
    }

    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassContainer(
                width: 38,
                height: 38,
                padding: EdgeInsets.zero,
                radius: 11,
                blur: 0,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.primary.withValues(alpha: 0.28),
                child: const Icon(Icons.display_settings_outlined,
                    size: 19, color: AuraColors.primary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text('Device status', style: text.titleLarge),
              ),
              StatusPill(
                label: _linkLabel(link.status),
                color: _linkColor(link.status),
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          if (paired != null)
            _PairedBody(device: paired, link: link, text: text)
          else
            _EmptyBody(
              discovery: discovery,
              pairing: pairing,
              link: link,
              text: text,
            ),
        ],
      ),
    );
  }

  String _linkLabel(DeviceLinkStatus status) => switch (status) {
        DeviceLinkStatus.notPaired => 'No panel',
        DeviceLinkStatus.disconnected => 'Disconnected',
        DeviceLinkStatus.connecting => 'Connecting',
        DeviceLinkStatus.connected => 'Connected',
        DeviceLinkStatus.unavailable => 'Unavailable',
      };

  Color _linkColor(DeviceLinkStatus status) => switch (status) {
        DeviceLinkStatus.connected => AuraColors.success,
        DeviceLinkStatus.connecting => AuraColors.secondary,
        DeviceLinkStatus.unavailable => AuraColors.danger,
        DeviceLinkStatus.disconnected ||
        DeviceLinkStatus.notPaired =>
          AuraColors.textSecondary,
      };
}

class _PairedBody extends StatelessWidget {
  const _PairedBody({
    required this.device,
    required this.link,
    required this.text,
  });

  final AuraDevice device;
  final DeviceLinkState link;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(device.name, style: text.headlineSmall),
        const SizedBox(height: AuraSpace.xxs),
        Text(
          '${device.model} · ${device.transport.label}',
          style: text.bodySmall,
        ),
        const SizedBox(height: AuraSpace.md),
        _Fact(label: 'State', value: device.connectionState.label),
        if (device.connectionQuality != DeviceConnectionQuality.unknown)
          _Fact(
            label: device.transport == DeviceTransport.wifi
                ? 'Wi-Fi signal'
                : 'Connection quality',
            value: _qualityLabel(device.connectionQuality),
          ),
        if (device.batteryPercent != null)
          _Fact(label: 'Power', value: '${device.batteryPercent}%'),
        if (device.firmwareVersion.trim().isNotEmpty)
          _Fact(label: 'Firmware', value: device.firmwareVersion),
        if (device.lastSeen != null)
          _Fact(
              label: 'Last seen', value: formatRelativeTime(device.lastSeen!)),
        if (link.changedAt != null)
          _Fact(
              label: 'Status changed',
              value: formatRelativeTime(link.changedAt!)),
        const SizedBox(height: AuraSpace.md),
        Wrap(
          spacing: AuraSpace.sm,
          runSpacing: AuraSpace.xs,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.devices),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open device'),
            ),
            OutlinedButton.icon(
              onPressed: () => context.go(AppRoutes.diagnostics),
              icon: const Icon(Icons.monitor_heart_outlined, size: 16),
              label: const Text('Diagnostics'),
            ),
          ],
        ),
      ],
    );
  }
}

class _EmptyBody extends ConsumerWidget {
  const _EmptyBody({
    required this.discovery,
    required this.pairing,
    required this.link,
    required this.text,
  });

  final DeviceDiscoveryState discovery;
  final DevicePairingState pairing;
  final DeviceLinkState link;
  final TextTheme text;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? problem = pairing.message ??
        (discovery.hasError ? discovery.message : null) ??
        (link.hasError ? link.message : null);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('No panel paired', style: text.titleLarge),
        const SizedBox(height: AuraSpace.xs),
        Text(
          'Connect your AURA display to manage its screen, wallpapers and '
          'settings from your phone.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: AuraSpace.sm),
        Text(
          _statusLine(discovery, pairing, link),
          style: text.bodySmall?.copyWith(color: AuraColors.textSecondary),
        ),
        if (problem != null) ...<Widget>[
          const SizedBox(height: AuraSpace.xs),
          Text(
            problem,
            style: text.bodySmall?.copyWith(color: AuraColors.warning),
          ),
          TextButton.icon(
            onPressed: () => context.go(AppRoutes.diagnostics),
            icon: const Icon(Icons.monitor_heart_outlined, size: 16),
            label: const Text('View diagnostics'),
          ),
        ],
        const SizedBox(height: AuraSpace.sm),
        Wrap(
          spacing: AuraSpace.sm,
          runSpacing: AuraSpace.xs,
          children: <Widget>[
            FilledButton.icon(
              onPressed: () => context.go(AppRoutes.devices),
              icon: const Icon(Icons.link_rounded, size: 16),
              label: const Text('Pair device'),
            ),
            OutlinedButton.icon(
              onPressed: discovery.isDiscovering
                  ? null
                  : () =>
                      ref.read(deviceConnectionProvider.notifier).discover(),
              icon: discovery.isDiscovering
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.radar_rounded, size: 16),
              label: Text(
                  discovery.isDiscovering ? 'Searching…' : 'Discover devices'),
            ),
          ],
        ),
      ],
    );
  }

  String _statusLine(
    DeviceDiscoveryState discovery,
    DevicePairingState pairing,
    DeviceLinkState link,
  ) {
    if (link.status == DeviceLinkStatus.unavailable) {
      return 'Device unavailable · no ESP32 transport is linked';
    }
    if (pairing.status == DevicePairingStatus.error) {
      return 'Connection failed · pairing did not complete';
    }
    if (pairing.isPairing) {
      return 'Pairing requested · awaiting device confirmation';
    }
    if (pairing.status == DevicePairingStatus.paired) {
      return 'Paired';
    }
    if (pairing.status == DevicePairingStatus.unavailable) {
      return 'Device unavailable · pairing is not supported yet';
    }
    if (discovery.isDiscovering) return 'Searching for AURA panels';
    if (discovery.status == DeviceDiscoveryStatus.available &&
        discovery.devices.isNotEmpty) {
      return '${discovery.devices.length} AURA device'
          '${discovery.devices.length == 1 ? '' : 's'} found';
    }
    if (discovery.status == DeviceDiscoveryStatus.error) {
      return 'Connection failed · discovery could not complete';
    }
    if (discovery.status == DeviceDiscoveryStatus.unavailable) {
      return 'Device unavailable until a device transport is installed';
    }
    return 'No device transport is connected';
  }
}

String _qualityLabel(DeviceConnectionQuality quality) => switch (quality) {
      DeviceConnectionQuality.excellent => 'Excellent',
      DeviceConnectionQuality.good => 'Good',
      DeviceConnectionQuality.fair => 'Fair',
      DeviceConnectionQuality.poor => 'Poor',
      DeviceConnectionQuality.unknown => 'Unknown',
    };

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xxs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}
