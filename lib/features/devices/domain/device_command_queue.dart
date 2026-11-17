import 'package:aura_hub/features/devices/domain/device_command.dart';

/// Bounded in-memory FIFO of commands waiting for a real transport.
///
/// This queue only STORES commands. It does not dispatch, transmit, or confirm
/// delivery: [DeviceCommandStatus.acknowledged] and
/// [DeviceCommandStatus.failed] are local state transitions recorded when a
/// caller reports them, not proof a device responded. A real transport adapter
/// must be added before any command can leave the app.
class DeviceCommandQueue {
  DeviceCommandQueue({this.capacity = maxPendingCommands})
      : assert(capacity > 0, 'capacity must be positive');

  /// Default hard bound so a long-running session cannot grow without limit.
  static const int maxPendingCommands = 100;

  final int capacity;
  final List<DeviceCommand> _commands = <DeviceCommand>[];

  int get length => _commands.length;
  bool get isEmpty => _commands.isEmpty;
  bool get isFull => _commands.length >= capacity;

  /// Adds [command] to the tail.
  ///
  /// Returns false at capacity. Accepted commands are never silently dropped.
  bool enqueue(DeviceCommand command) {
    if (isFull) return false;
    _commands.add(command);
    return true;
  }

  /// First still-pending command, or null. Never changes status or removes it.
  DeviceCommand? peek() {
    for (final DeviceCommand command in _commands) {
      if (_isPending(command)) return command;
    }
    return null;
  }

  /// Marks a pending command acknowledged and returns the updated command.
  ///
  /// Returns null for an unknown id or a command already in a terminal state.
  DeviceCommand? acknowledge(String id) =>
      _transition(id, DeviceCommandStatus.acknowledged);

  /// Marks a pending command failed and returns the updated command.
  DeviceCommand? markFailed(String id) =>
      _transition(id, DeviceCommandStatus.failed);

  DeviceCommand? _transition(String id, DeviceCommandStatus status) {
    final int index = _commands.indexWhere((DeviceCommand c) => c.id == id);
    if (index < 0) return null;
    final DeviceCommand command = _commands[index];
    if (!_isPending(command)) return null;
    final DeviceCommand updated = command.copyWith(status: status);
    _commands[index] = updated;
    return updated;
  }

  /// Removes a command by id and returns it, or null when not present.
  DeviceCommand? remove(String id) {
    final int index = _commands.indexWhere((DeviceCommand c) => c.id == id);
    if (index < 0) return null;
    return _commands.removeAt(index);
  }

  void clear() => _commands.clear();

  /// Pending commands in FIFO order.
  ///
  /// Terminal commands remain stored for inspection but are excluded here.
  List<DeviceCommand> get pendingCommands =>
      List<DeviceCommand>.unmodifiable(_commands.where(_isPending).toList());

  static bool _isPending(DeviceCommand command) =>
      command.status == DeviceCommandStatus.queued ||
      command.status == DeviceCommandStatus.dispatched;
}
