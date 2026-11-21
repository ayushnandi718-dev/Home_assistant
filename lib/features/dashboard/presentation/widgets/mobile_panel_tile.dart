import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/aura_tile.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Panel state comes only from the real device link controller. No Wi-Fi, RSSI
/// or firmware claims are made without a reported capability.
class MobilePanelTile extends ConsumerWidget {
  const MobilePanelTile({super.key});

  static const Key tileKey = ValueKey<String>('panel-tile');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceLinkState link = ref.watch(deviceLinkProvider);
    final List<AuraDeviceSummary> devices = ref
            .watch(devicesProvider)
            .valueOrNull
            ?.map(
              (device) => AuraDeviceSummary(
                id: device.id,
                name: device.name,
              ),
            )
            .toList() ??
        const <AuraDeviceSummary>[];

    final List<String> matchedNames = devices
        .where((AuraDeviceSummary device) => device.id == link.deviceId)
        .map((AuraDeviceSummary device) => device.name)
        .toList();
    final String? deviceName = matchedNames.isEmpty ? null : matchedNames.first;

    final String value;
    final String sub;
    final IconData icon;
    final Color accent;

    switch (link.status) {
      case DeviceLinkStatus.notPaired:
        value = 'Not paired';
        sub = 'Tap to pair';
        icon = Icons.wifi_off_rounded;
        accent = const Color(0xFF8AB4FF);
      case DeviceLinkStatus.disconnected:
        value = 'Disconnected';
        sub = 'Tap to reconnect';
        icon = Icons.link_off_rounded;
        accent = AuraColors.warning;
      case DeviceLinkStatus.connecting:
        value = 'Connecting…';
        sub = 'Waiting for panel';
        icon = Icons.sync_rounded;
        accent = AuraColors.primary;
      case DeviceLinkStatus.connected:
        value = deviceName ?? 'Connected';
        sub = 'Panel link active';
        icon = Icons.display_settings_rounded;
        accent = AuraColors.success;
      case DeviceLinkStatus.unavailable:
        value = 'Unavailable';
        sub = 'Panel state could not be read';
        icon = Icons.help_outline_rounded;
        accent = AuraColors.textSecondary;
    }

    return SizedBox(
      key: tileKey,
      width: double.infinity,
      child: AuraTile(
        icon: icon,
        accent: accent,
        label: 'AURA panel',
        value: value,
        sub: sub,
        height: 132,
        tooltip: 'Open device pairing',
        onTap: () => context.go(AppRoutes.devices),
      ),
    );
  }
}

/// Small projection of a real registered device. Kept local so the tile never
/// depends on demo data or on fields the repository cannot actually report.
class AuraDeviceSummary {
  const AuraDeviceSummary({required this.id, required this.name});

  final String id;
  final String name;
}
