import 'package:aura_hub/features/devices/domain/aura_device.dart';

/// Discovery, pairing and connection are deliberately separate transitions.
/// See [DeviceTransport] in `aura_device.dart` for transport identity.
enum DeviceDiscoveryStatus { idle, discovering, available, unavailable, error }

class DeviceDiscoveryState {
  const DeviceDiscoveryState({
    this.status = DeviceDiscoveryStatus.idle,
    this.devices = const <AuraDevice>[],
    this.message,
  });

  final DeviceDiscoveryStatus status;
  final List<AuraDevice> devices;
  final String? message;

  bool get isDiscovering => status == DeviceDiscoveryStatus.discovering;
  bool get hasError => status == DeviceDiscoveryStatus.error;
  bool get canPair =>
      status == DeviceDiscoveryStatus.available && devices.isNotEmpty;
}

enum DevicePairingStatus { idle, pairing, paired, unavailable, error }

class DevicePairingState {
  const DevicePairingState({
    this.status = DevicePairingStatus.idle,
    this.message,
  });

  final DevicePairingStatus status;
  final String? message;

  bool get isPairing => status == DevicePairingStatus.pairing;
  bool get hasError => status == DevicePairingStatus.error;
}

/// Connection is a separate transition from discovery and pairing. It never
/// reports a link merely because the Windows telemetry API is reachable.
enum DeviceLinkStatus {
  notPaired,
  disconnected,
  connecting,
  connected,
  unavailable
}

class DeviceLinkState {
  const DeviceLinkState({
    this.status = DeviceLinkStatus.notPaired,
    this.deviceId,
    this.message,
    this.changedAt,
  });

  final DeviceLinkStatus status;
  final String? deviceId;
  final String? message;
  final DateTime? changedAt;

  bool get isConnected => status == DeviceLinkStatus.connected;
  bool get hasError => status == DeviceLinkStatus.unavailable;
}

/// Result returned by a transport adapter after it has looked for devices.
class DeviceDiscoveryResult {
  const DeviceDiscoveryResult.available(this.devices)
      : status = DeviceDiscoveryStatus.available,
        message = null;

  const DeviceDiscoveryResult.unavailable(this.message)
      : status = DeviceDiscoveryStatus.unavailable,
        devices = const <AuraDevice>[];

  const DeviceDiscoveryResult.failure(this.message)
      : status = DeviceDiscoveryStatus.error,
        devices = const <AuraDevice>[];

  final DeviceDiscoveryStatus status;
  final List<AuraDevice> devices;
  final String? message;
}

/// Result returned by a transport adapter when a user starts pairing.
class DevicePairingResult {
  const DevicePairingResult.paired(this.device)
      : status = DevicePairingStatus.paired,
        message = null;

  const DevicePairingResult.unavailable(this.message)
      : status = DevicePairingStatus.unavailable,
        device = null;

  const DevicePairingResult.failure(this.message)
      : status = DevicePairingStatus.error,
        device = null;

  final DevicePairingStatus status;
  final AuraDevice? device;
  final String? message;
}
