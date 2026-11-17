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
  final DeviceConnectionState connectionState;
  final DeviceConnectionQuality connectionQuality;
  final bool isDemo;
  final int? batteryPercent;
  final DateTime? lastSeen;
  final DateTime? lastSynced;

  bool get isOnline => connectionState == DeviceConnectionState.online;
}
