import 'package:aura_hub/features/devices/data/local_device_repository.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/domain/device_repository.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:flutter_test/flutter_test.dart';

/// Injected transport double used to prove the state machine transitions
/// without fabricating devices in the real application repository.
class FakeDeviceRepository implements DeviceRepository {
  FakeDeviceRepository({
    this.discoveryResult,
    this.pairingResult,
    DeviceLinkState? link,
  }) : link = link ?? const DeviceLinkState();

  DeviceDiscoveryResult? discoveryResult;
  DevicePairingResult? pairingResult;
  DeviceLinkState link;

  static const AuraDevice device = AuraDevice(
    id: 'aura-stable-id-001',
    name: 'AURA One',
    model: 'ESP32',
    firmwareVersion: '1.0.0',
    transport: DeviceTransport.bluetoothLowEnergy,
    connectionState: DeviceConnectionState.offline,
    connectionQuality: DeviceConnectionQuality.unknown,
    isDemo: false,
  );

  @override
  Future<List<AuraDevice>> fetchDevices() async => const <AuraDevice>[];

  @override
  Future<DeviceDiscoveryResult> discover() async =>
      discoveryResult ??
      const DeviceDiscoveryResult.unavailable('no transport');

  @override
  Future<DevicePairingResult> pair(String deviceId) async =>
      pairingResult ?? const DevicePairingResult.unavailable('no transport');

  @override
  Future<DeviceLinkState> currentLink() async => link;
}

void main() {
  test('local device transport truthfully reports discovery unavailable',
      () async {
    final DeviceDiscoveryResult result =
        await const LocalDeviceRepository().discover();

    expect(result.status, DeviceDiscoveryStatus.unavailable);
    expect(result.devices, isEmpty);
    expect(result.message, contains('No device scan was simulated'));
  });

  test('local repository invents no devices and reports an unpaired link',
      () async {
    const LocalDeviceRepository repository = LocalDeviceRepository();
    expect(await repository.fetchDevices(), isEmpty);
    final DeviceLinkState link = await repository.currentLink();
    expect(link.status, DeviceLinkStatus.notPaired);
    expect(link.isConnected, isFalse);
  });

  test('controller exposes discovery progress and final transport state',
      () async {
    final DeviceConnectionController controller =
        DeviceConnectionController(const LocalDeviceRepository());
    addTearDown(controller.dispose);

    final Future<void> discovery = controller.discover();
    expect(controller.state.status, DeviceDiscoveryStatus.discovering);
    await discovery;
    expect(controller.state.status, DeviceDiscoveryStatus.unavailable);
  });

  test('discovery failure produces a clear error state, not fake devices',
      () async {
    final DeviceConnectionController controller = DeviceConnectionController(
      FakeDeviceRepository(
        discoveryResult: const DeviceDiscoveryResult.failure('scan crashed'),
      ),
    );
    addTearDown(controller.dispose);

    await controller.discover();
    expect(controller.state.status, DeviceDiscoveryStatus.error);
    expect(controller.state.hasError, isTrue);
    expect(controller.state.devices, isEmpty);
    expect(controller.state.message, contains('scan crashed'));
    expect(controller.state.canPair, isFalse);
  });

  test('discovery availability enables pairing by stable device id', () async {
    final FakeDeviceRepository repository = FakeDeviceRepository(
      discoveryResult: const DeviceDiscoveryResult.available(
        <AuraDevice>[FakeDeviceRepository.device],
      ),
      pairingResult: const DevicePairingResult.paired(
        FakeDeviceRepository.device,
      ),
    );
    final DeviceConnectionController discovery =
        DeviceConnectionController(repository);
    addTearDown(discovery.dispose);
    await discovery.discover();

    expect(discovery.state.status, DeviceDiscoveryStatus.available);
    expect(discovery.state.canPair, isTrue);
    expect(discovery.state.devices.single.id, 'aura-stable-id-001');

    final DevicePairingController pairing = DevicePairingController(repository);
    addTearDown(pairing.dispose);
    await pairing.pair('aura-stable-id-001');
    expect(pairing.state.status, DevicePairingStatus.paired);
    expect(pairing.state.isPairing, isFalse);
  });

  test('pairing error is explicit and a later success clears it', () async {
    final FakeDeviceRepository repository = FakeDeviceRepository(
      pairingResult: const DevicePairingResult.failure('auth rejected'),
    );
    final DevicePairingController pairing = DevicePairingController(repository);
    addTearDown(pairing.dispose);

    await pairing.pair('aura-stable-id-001');
    expect(pairing.state.status, DevicePairingStatus.error);
    expect(pairing.state.hasError, isTrue);
    expect(pairing.state.message, contains('auth rejected'));

    repository.pairingResult = const DevicePairingResult.paired(
      FakeDeviceRepository.device,
    );
    await pairing.pair('aura-stable-id-001');
    expect(pairing.state.status, DevicePairingStatus.paired);
    expect(pairing.state.message, isNull);
    expect(pairing.state.hasError, isFalse);
  });

  test('link state stays independent of discovery and pairing', () async {
    final DeviceLinkController link = DeviceLinkController(
      FakeDeviceRepository(
        link: const DeviceLinkState(
          status: DeviceLinkStatus.connected,
          deviceId: 'aura-stable-id-001',
        ),
      ),
    );
    addTearDown(link.dispose);

    await link.refresh();
    expect(link.state.isConnected, isTrue);
    expect(link.state.deviceId, 'aura-stable-id-001');
  });
}
