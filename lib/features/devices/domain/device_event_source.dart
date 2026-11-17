import 'dart:async';

import 'package:aura_hub/features/devices/domain/device_event.dart';

/// Boundary for a future transport that streams real device events.
///
/// A real BLE or Wi-Fi adapter implements this once hardware exists. Until
/// then, consumers depend on the interface rather than inventing telemetry.
abstract class DeviceEventSource {
  Stream<DeviceEvent> get events;
}

/// Empty implementation that exists only so providers can depend on
/// [DeviceEventSource] without inventing devices, connections or telemetry.
///
/// It emits no events and completes immediately. This is not a simulated
/// device and not a connection: a real adapter replaces it in the future.
class NoDeviceEventSource implements DeviceEventSource {
  const NoDeviceEventSource();

  @override
  Stream<DeviceEvent> get events => const Stream<DeviceEvent>.empty();
}
