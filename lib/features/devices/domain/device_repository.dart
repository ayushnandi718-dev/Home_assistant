import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';

/// Transport-neutral boundary for current local state and future BLE / Wi-Fi
/// implementations.
///
/// A future BLE or Wi-Fi adapter implements this same contract and is injected
/// through `deviceRepositoryProvider`; the Devices page does not change.
/// Discovery, pairing and connection are explicit, separate transitions so an
/// unavailable transport can never be rendered as a successful pairing.
abstract class DeviceRepository {
  /// Stable, already-paired devices. Empty until a real transport exists.
  Future<List<AuraDevice>> fetchDevices();

  /// Searches for devices using the transport's own implementation.
  Future<DeviceDiscoveryResult> discover();

  /// Starts a pairing state machine for one device id.
  ///
  /// Implementations must never store Wi-Fi passwords or device secrets in
  /// ordinary application preferences.
  Future<DevicePairingResult> pair(String deviceId);

  /// Current connection state, independent of discovery and pairing.
  Future<DeviceLinkState> currentLink();
}
