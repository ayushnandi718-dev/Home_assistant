import 'package:aura_hub/features/devices/domain/device_capability.dart';
import 'package:aura_hub/features/devices/domain/device_command.dart';
import 'package:aura_hub/features/devices/domain/device_command_queue.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/domain/device_event.dart';
import 'package:aura_hub/features/devices/domain/device_event_source.dart';
import 'package:aura_hub/features/devices/domain/device_status.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime _timestamp = DateTime.utc(2026, 11, 17, 10, 30);

DeviceCommand _command(String id) => DeviceCommand(
      id: id,
      targetDeviceId: 'future-waveshare-s3',
      type: DeviceCommandType.ping,
      createdAt: _timestamp,
    );

void main() {
  group('DeviceCapabilities', () {
    test('supports answers only for explicitly listed capabilities', () {
      const DeviceCapabilities capabilities = DeviceCapabilities(
        capabilities: <DeviceCapability>{
          DeviceCapability.display,
          DeviceCapability.ota,
        },
        firmwareVersion: '0.0.0-contract',
      );

      expect(capabilities.supports(DeviceCapability.display), isTrue);
      expect(capabilities.supports(DeviceCapability.ota), isTrue);
      expect(capabilities.supports(DeviceCapability.microphone), isFalse);
    });

    test('JSON round trip and equality ignore insertion order', () {
      const DeviceCapabilities first = DeviceCapabilities(
        capabilities: <DeviceCapability>{
          DeviceCapability.led,
          DeviceCapability.gpio,
        },
        firmwareVersion: '1.2.3',
        protocolVersion: 'proto-2',
      );
      final DeviceCapabilities second = DeviceCapabilities(
        capabilities: <DeviceCapability>{
          DeviceCapability.gpio,
          DeviceCapability.led,
        },
        firmwareVersion: '1.2.3',
        protocolVersion: 'proto-2',
      );

      final DeviceCapabilities decoded =
          DeviceCapabilities.fromJson(first.toJson());
      expect(decoded, first);
      expect(decoded, second);
      expect(decoded.hashCode, first.hashCode);
      expect(decoded.supports(DeviceCapability.gpio), isTrue);
    });
  });

  group('DeviceEvent', () {
    test('JSON round trip preserves identity, type and payload', () {
      final DeviceEvent event = DeviceEvent(
        id: 'event-1',
        deviceId: 'future-device',
        type: DeviceEventType.button,
        timestamp: _timestamp,
        payload: <String, dynamic>{'button': 'a', 'count': 1},
      );

      final DeviceEvent decoded = DeviceEvent.fromJson(event.toJson());
      expect(decoded, event);
      expect(decoded.type, DeviceEventType.button);
      expect(decoded.payload['button'], 'a');
    });

    test('bounded factory caps payload without inventing values', () {
      final Map<String, dynamic> payload = <String, dynamic>{
        for (int i = 0; i < DeviceEvent.maxPayloadEntries + 5; i++) 'key$i': i,
      };
      final DeviceEvent event = DeviceEvent.bounded(
        id: 'event-bounded',
        deviceId: 'future-device',
        type: DeviceEventType.telemetry,
        timestamp: _timestamp,
        payload: payload,
      );

      expect(event.payload.length, DeviceEvent.maxPayloadEntries);
      expect(payload.length, DeviceEvent.maxPayloadEntries + 5,
          reason: 'the source map is not modified');
    });
  });

  group('DeviceCommand', () {
    test('JSON round trip preserves fields, status and equality', () {
      final DeviceCommand command = DeviceCommand(
        id: 'cmd-1',
        targetDeviceId: 'future-device',
        type: DeviceCommandType.setBrightness,
        createdAt: _timestamp,
        payload: <String, dynamic>{'brightness': 80},
        status: DeviceCommandStatus.queued,
      );

      final DeviceCommand decoded = DeviceCommand.fromJson(command.toJson());
      expect(decoded, command);
      expect(decoded.status, DeviceCommandStatus.queued);

      final DeviceCommand acknowledged =
          decoded.copyWith(status: DeviceCommandStatus.acknowledged);
      expect(acknowledged.status, DeviceCommandStatus.acknowledged);
      expect(acknowledged.id, decoded.id);
      expect(decoded.status, DeviceCommandStatus.queued,
          reason: 'copyWith does not mutate the original');
    });
  });

  group('DeviceCommandQueue', () {
    test('keeps FIFO order and a filtered pending view', () {
      final DeviceCommandQueue queue = DeviceCommandQueue(capacity: 3);
      expect(queue.enqueue(_command('a')), isTrue);
      expect(queue.enqueue(_command('b')), isTrue);
      expect(queue.enqueue(_command('c')), isTrue);

      expect(queue.peek()?.id, 'a');
      expect(
        queue.pendingCommands.map((DeviceCommand c) => c.id).toList(),
        <String>['a', 'b', 'c'],
      );

      expect(queue.acknowledge('a')?.status, DeviceCommandStatus.acknowledged);
      expect(queue.peek()?.id, 'b');
      expect(
        queue.pendingCommands.map((DeviceCommand c) => c.id).toList(),
        <String>['b', 'c'],
      );
    });

    test('bounds storage and rejects overflow instead of dropping work', () {
      final DeviceCommandQueue queue = DeviceCommandQueue(capacity: 2);
      expect(queue.enqueue(_command('a')), isTrue);
      expect(queue.enqueue(_command('b')), isTrue);
      expect(queue.enqueue(_command('c')), isFalse);
      expect(queue.length, 2);
      expect(queue.isFull, isTrue);
      expect(
        queue.pendingCommands.map((DeviceCommand c) => c.id).toList(),
        <String>['a', 'b'],
      );
    });

    test('ack, fail, remove and clear are explicit and deterministic', () {
      final DeviceCommandQueue queue = DeviceCommandQueue(capacity: 4);
      queue.enqueue(_command('a'));
      queue.enqueue(_command('b'));
      queue.enqueue(_command('c'));

      expect(queue.markFailed('b')?.status, DeviceCommandStatus.failed);
      expect(queue.acknowledge('b'), isNull,
          reason: 'terminal commands are not acknowledged twice');
      expect(queue.peek()?.id, 'a');
      expect(queue.remove('a')?.id, 'a');
      expect(queue.remove('a'), isNull);
      expect(queue.peek()?.id, 'c');
      queue.clear();
      expect(queue.isEmpty, isTrue);
      expect(queue.peek(), isNull);
    });
  });

  group('DeviceEventSource', () {
    test('NoDeviceEventSource emits nothing', () async {
      final DeviceEventSource source = const NoDeviceEventSource();
      expect(await source.events.toList(), isEmpty);
      await expectLater(source.events, emitsDone);
    });
  });

  group('DeviceStatusSnapshot', () {
    test('JSON round trip preserves the link state and capabilities', () {
      final DeviceStatusSnapshot snapshot = DeviceStatusSnapshot(
        deviceId: 'future-device',
        connection: const DeviceLinkState(
          status: DeviceLinkStatus.notPaired,
          message: 'No transport yet',
        ),
        capabilities: const DeviceCapabilities(
          capabilities: <DeviceCapability>{DeviceCapability.display},
        ),
        lastUpdated: _timestamp,
      );

      final DeviceStatusSnapshot decoded =
          DeviceStatusSnapshot.fromJson(snapshot.toJson());
      expect(decoded, snapshot);
      expect(decoded.isConnected, isFalse);
      expect(decoded.connection.status, DeviceLinkStatus.notPaired);
      expect(decoded.capabilities?.supports(DeviceCapability.display), isTrue);
    });
  });
}
