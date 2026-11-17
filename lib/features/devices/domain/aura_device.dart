/// Transport a device is reached through. Kept in the domain model so a future
/// BLE or Wi-Fi adapter cannot be confused with a Windows host reading.
enum DeviceTransport { bluetoothLowEnergy, wifi }

extension DeviceTransportLabel on DeviceTransport {
  String get label => switch (this) {
        DeviceTransport.bluetoothLowEnergy => 'BLE',
        DeviceTransport.wifi => 'Wi-Fi',
      };
}

enum DeviceConnectionState { online, offline, connecting }

enum DeviceConnectionQuality { excellent, good, fair, poor, unknown }

extension DeviceConnectionStateLabel on DeviceConnectionState {
  String get label {
    switch (this) {
      case DeviceConnectionState.online:
        return 'Connected';
      case DeviceConnectionState.offline:
        return 'Offline';
      case DeviceConnectionState.connecting:
        return 'Connecting';
    }
  }
}

class AuraDevice {
  const AuraDevice({
    required this.id,
    required this.name,
    required this.model,
    required this.firmwareVersion,
    required this.transport,
    required this.connectionState,
    required this.connectionQuality,
    required this.isDemo,
    this.batteryPercent,
    this.lastSeen,
    this.lastSynced,
  });

  final String id;
  final String name;
  final String model;
  final String firmwareVersion;

  /// Physical transport. A stable id, not a display name, is the identity.
  final DeviceTransport transport;
  final DeviceConnectionState connectionState;
  final DeviceConnectionQuality connectionQuality;
  final bool isDemo;
  final int? batteryPercent;
  final DateTime? lastSeen;
  final DateTime? lastSynced;

  bool get isOnline => connectionState == DeviceConnectionState.online;
}
