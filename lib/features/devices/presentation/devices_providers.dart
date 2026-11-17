import 'package:aura_hub/features/devices/data/local_device_repository.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<DeviceRepository> deviceRepositoryProvider =
    Provider<DeviceRepository>((Ref ref) {
  return const LocalDeviceRepository();
});

/// Returns the real (currently empty) device list. Refreshing re-runs the
/// repository without fabricating hardware.
final FutureProvider<List<AuraDevice>> devicesProvider =
    FutureProvider<List<AuraDevice>>((Ref ref) async {
  return ref.watch(deviceRepositoryProvider).fetchDevices();
});
