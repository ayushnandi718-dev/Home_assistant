import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';

/// Honest device source for the foundation build.
///
/// This app has no AURA ESP32 communication stack yet, so discovery always
/// reports an empty list and pairing/connection are unavailable. No device is
/// invented to make the UI look populated, and no secret is stored.
class LocalDeviceRepository implements DeviceRepository {
  const LocalDeviceRepository();

  @override
  Future<List<AuraDevice>> fetchDevices() async => const <AuraDevice>[];

  @override
  Future<DeviceDiscoveryResult> discover() async =>
      const DeviceDiscoveryResult.unavailable(
        'BLE and Wi-Fi discovery need an AURA transport implementation. '
        'No device scan was simulated.',
      );

  @override
  Future<DevicePairingResult> pair(String deviceId) async =>
      const DevicePairingResult.unavailable(
        'Pairing is unavailable until an AURA BLE or Wi-Fi transport is added. '
        'No device secrets are stored in app preferences.',
      );

  @override
  Future<DeviceLinkState> currentLink() async =>
      const DeviceLinkState(status: DeviceLinkStatus.notPaired);
}
