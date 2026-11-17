import 'package:aura_hub/features/devices/domain/aura_device.dart';

/// Boundary for current mock and future BLE / Wi-Fi device implementations.
abstract class DeviceRepository {
  Future<List<AuraDevice>> fetchDevices();
}
