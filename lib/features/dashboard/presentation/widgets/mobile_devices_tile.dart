import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/aura_tile.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Counts only genuinely registered, online AURA devices. Network neighbours
/// are never treated as devices.
class MobileDevicesTile extends ConsumerWidget {
  const MobileDevicesTile({super.key});

  static const Key tileKey = ValueKey<String>('devices-tile');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<AuraDevice>> devices = ref.watch(devicesProvider);
    final DeviceDiscoveryState discovery = ref.watch(deviceConnectionProvider);
    final bool hasError = devices.hasError;

    final String value;
    final String sub;
    final AuraTileState state;

    if (hasError) {
      value = 'Unavailable';
      sub = 'Device list could not be read';
      state = AuraTileState.unavailable;
    } else {
      final int connected = devices.valueOrNull
              ?.where((device) => device.isOnline && !device.isDemo)
              .length ??
          0;
      value = '$connected';
      sub = discovery.isDiscovering
          ? 'Discovering AURA devices…'
          : 'registered AURA devices';
      state = AuraTileState.normal;
    }

    return SizedBox(
      key: tileKey,
      width: double.infinity,
      child: AuraTile(
        icon: Icons.devices_rounded,
        accent: const Color(0xFF7EE0B5),
        label: 'Connected devices',
        value: value,
        sub: sub,
        height: 132,
        state: state,
        tooltip: 'Open Devices',
        onTap: () => context.go(AppRoutes.devices),
      ),
    );
  }
}
