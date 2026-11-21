import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/aura_tile.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small facts that are useful at a glance but unsupported on this build are
/// shown as unavailable. No SSID, RSSI, uptime or phone battery is fabricated.
class MobileGlanceTiles extends ConsumerWidget {
  const MobileGlanceTiles({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceLinkState link = ref.watch(deviceLinkProvider);
    final List<AuraDevice> devices =
        ref.watch(devicesProvider).valueOrNull ?? const <AuraDevice>[];

    final DateTime? lastSeen =
        link.changedAt ?? _deviceLastSeen(devices, link.deviceId);
    final bool panelAvailable = link.isConnected && link.deviceId != null;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double tileWidth = (constraints.maxWidth - 12) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  key: const ValueKey<String>('phone-wifi-tile'),
                  width: tileWidth,
                  child: const AuraTile(
                    icon: Icons.wifi_off_rounded,
                    accent: Color(0xFF8AB4FF),
                    label: 'Phone Wi-Fi',
                    value: 'Unavailable',
                    sub: 'No Wi-Fi API on this build',
                    height: 118,
                    state: AuraTileState.unavailable,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  key: const ValueKey<String>('phone-battery-tile'),
                  width: tileWidth,
                  child: const AuraTile(
                    icon: Icons.battery_unknown_rounded,
                    accent: Color(0xFF7EE0B5),
                    label: 'Phone battery',
                    value: 'Unavailable',
                    sub: 'No battery API on this build',
                    height: 118,
                    state: AuraTileState.unavailable,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                SizedBox(
                  key: const ValueKey<String>('panel-wifi-tile'),
                  width: tileWidth,
                  child: AuraTile(
                    icon: Icons.wifi_rounded,
                    accent: AuraColors.primary,
                    label: 'Panel Wi-Fi',
                    value: panelAvailable ? 'Not reported' : 'Not paired',
                    sub: panelAvailable
                        ? 'SSID and RSSI need panel support'
                        : 'Available when paired',
                    height: 118,
                    state: AuraTileState.unavailable,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  key: const ValueKey<String>('panel-last-seen-tile'),
                  width: tileWidth,
                  child: AuraTile(
                    icon: Icons.history_toggle_off_rounded,
                    accent: const Color(0xFFB69CFF),
                    label: 'Panel last seen',
                    value: lastSeen == null
                        ? 'No data'
                        : formatRelativeTime(lastSeen),
                    sub: lastSeen == null
                        ? 'Never reported'
                        : 'From real link state',
                    height: 118,
                    state: lastSeen == null
                        ? AuraTileState.unavailable
                        : AuraTileState.normal,
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  DateTime? _deviceLastSeen(List<AuraDevice> devices, String? deviceId) {
    if (deviceId == null) return null;
    for (final AuraDevice device in devices) {
      if (device.id == deviceId) return device.lastSeen;
    }
    return null;
  }
}
