import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';

/// Honest device source for the foundation build.
///
/// This app has no AURA ESP32 communication stack yet, so discovery always
/// reports an empty list. No device is invented to make the UI look populated.
class LocalDeviceRepository implements DeviceRepository {
  const LocalDeviceRepository();

  @override
  Future<List<AuraDevice>> fetchDevices() async => const <AuraDevice>[];
}
