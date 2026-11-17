import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';

/// Demonstration-only repository. It never talks to hardware.
class MockDeviceRepository implements DeviceRepository {
  const MockDeviceRepository({
    this.latency = const Duration(milliseconds: 350),
  });

  final Duration latency;

  @override
  Future<List<AuraDevice>> fetchDevices() async {
    if (latency > Duration.zero) {
      await Future<void>.delayed(latency);
    }
    final DateTime now = DateTime.now();
    return <AuraDevice>[
      AuraDevice(
        id: 'demo-device-001',
        name: 'AURA Desk',
        model: 'Waveshare ESP32-S3 Touch LCD 4.3B',
        firmwareVersion: '0.1.0-preview',
        connectionState: DeviceConnectionState.offline,
        connectionQuality: DeviceConnectionQuality.unknown,
        batteryPercent: null,
        lastSeen: now.subtract(const Duration(hours: 2, minutes: 15)),
        lastSynced: null,
        isDemo: true,
      ),
    ];
  }
}
