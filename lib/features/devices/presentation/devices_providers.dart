import 'dart:async';

import 'package:aura_hub/features/devices/data/local_device_repository.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
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

/// Owns discovery transitions. The name is retained for API compatibility;
/// discovery, pairing and connection are separate notifiers below.
class DeviceConnectionController extends StateNotifier<DeviceDiscoveryState> {
  DeviceConnectionController(this._repository, {DiagnosticRecorder? onEvent})
      : _onEvent = onEvent,
        super(const DeviceDiscoveryState());

  final DeviceRepository _repository;
  final DiagnosticRecorder? _onEvent;

  Future<void> discover() async {
    if (state.isDiscovering) return;
    final Stopwatch stopwatch = Stopwatch()..start();
    state = const DeviceDiscoveryState(
      status: DeviceDiscoveryStatus.discovering,
    );
    try {
      final DeviceDiscoveryResult result = await _repository.discover();
      state = DeviceDiscoveryState(
        status: result.status,
        devices: result.devices,
        message: result.message,
      );
      _onEvent?.call(
        DiagnosticCategory.deviceDiscovery,
        result.status == DeviceDiscoveryStatus.available
            ? 'Discovery found ${result.devices.length} device(s).'
            : result.message ?? 'Discovery returned ${result.status.name}.',
        succeeded: result.status != DeviceDiscoveryStatus.error,
        error: result.status == DeviceDiscoveryStatus.error
            ? result.message
            : null,
        duration: stopwatch.elapsed,
      );
    } catch (error) {
      state = DeviceDiscoveryState(
        status: DeviceDiscoveryStatus.error,
        message: 'Discovery failed: $error',
      );
      _onEvent?.call(
        DiagnosticCategory.deviceDiscovery,
        'Discovery raised an unexpected error.',
        succeeded: false,
        error: error.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }
}

final StateNotifierProvider<DeviceConnectionController, DeviceDiscoveryState>
    deviceConnectionProvider =
    StateNotifierProvider<DeviceConnectionController, DeviceDiscoveryState>(
  (Ref ref) => DeviceConnectionController(
    ref.watch(deviceRepositoryProvider),
    onEvent: ref.read(diagnosticEventsProvider.notifier).record,
  ),
);

class DevicePairingController extends StateNotifier<DevicePairingState> {
  DevicePairingController(this._repository, {DiagnosticRecorder? onEvent})
      : _onEvent = onEvent,
        super(const DevicePairingState());

  final DeviceRepository _repository;
  final DiagnosticRecorder? _onEvent;

  Future<void> pair(String deviceId) async {
    if (state.isPairing) return;
    final Stopwatch stopwatch = Stopwatch()..start();
    state = const DevicePairingState(status: DevicePairingStatus.pairing);
    try {
      final DevicePairingResult result = await _repository.pair(deviceId);
      state =
          DevicePairingState(status: result.status, message: result.message);
      _onEvent?.call(
        DiagnosticCategory.devicePairing,
        result.status == DevicePairingStatus.paired
            ? 'Pairing completed for a stable device id.'
            : result.message ?? 'Pairing returned ${result.status.name}.',
        succeeded: result.status == DevicePairingStatus.paired,
        error:
            result.status == DevicePairingStatus.error ? result.message : null,
        duration: stopwatch.elapsed,
      );
    } catch (error) {
      state = DevicePairingState(
        status: DevicePairingStatus.error,
        message: 'Pairing failed: $error',
      );
      _onEvent?.call(
        DiagnosticCategory.devicePairing,
        'Pairing raised an unexpected error.',
        succeeded: false,
        error: error.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }
}

final StateNotifierProvider<DevicePairingController, DevicePairingState>
    devicePairingProvider =
    StateNotifierProvider<DevicePairingController, DevicePairingState>(
  (Ref ref) => DevicePairingController(
    ref.watch(deviceRepositoryProvider),
    onEvent: ref.read(diagnosticEventsProvider.notifier).record,
  ),
);

/// Connection state is intentionally independent of discovery and pairing.
class DeviceLinkController extends StateNotifier<DeviceLinkState> {
  DeviceLinkController(this._repository, {DiagnosticRecorder? onEvent})
      : _onEvent = onEvent,
        super(const DeviceLinkState());

  final DeviceRepository _repository;
  final DiagnosticRecorder? _onEvent;

  Future<void> refresh() async {
    try {
      final DeviceLinkState next = await _repository.currentLink();
      state = next;
      _onEvent?.call(
        DiagnosticCategory.deviceConnection,
        'Device link is ${next.status.name}.',
        succeeded: next.status != DeviceLinkStatus.unavailable,
      );
    } catch (error) {
      state = const DeviceLinkState(
        status: DeviceLinkStatus.unavailable,
        message: 'Connection state could not be read.',
      );
      _onEvent?.call(
        DiagnosticCategory.deviceConnection,
        'Reading device connection state failed.',
        succeeded: false,
        error: error.toString(),
      );
    }
  }
}

final StateNotifierProvider<DeviceLinkController, DeviceLinkState>
    deviceLinkProvider =
    StateNotifierProvider<DeviceLinkController, DeviceLinkState>(
  (Ref ref) {
    final DeviceLinkController controller = DeviceLinkController(
      ref.watch(deviceRepositoryProvider),
      onEvent: ref.read(diagnosticEventsProvider.notifier).record,
    );
    scheduleMicrotask(controller.refresh);
    return controller;
  },
);
