/// Command kinds a future adapter may support.
///
/// Nothing here sends a command. These values are only the vocabulary for a
/// future transport contract with a Waveshare ESP32-S3 class device, which has
/// not been ordered and has no transport yet.
enum DeviceCommandType { ping, setBrightness, reboot }

/// Lifecycle of a command.
///
/// Only a real transport adapter may set [DeviceCommandStatus.dispatched],
/// [DeviceCommandStatus.acknowledged] or [DeviceCommandStatus.failed]. A queue
/// changing these states would pretend delivery that never happened.
enum DeviceCommandStatus { queued, dispatched, acknowledged, failed }

/// Immutable command addressed to a stable device id.
///
/// This is stored intent only: creating one never leaves the app and never
/// implies a device received it. [payload] keys are strings only and the map
/// is unmodifiable.
class DeviceCommand {
  DeviceCommand({
    required this.id,
    required this.targetDeviceId,
    required this.type,
    required this.createdAt,
    Map<String, dynamic> payload = const <String, dynamic>{},
    this.status = DeviceCommandStatus.queued,
  }) : payload = Map<String, dynamic>.unmodifiable(payload);

  final String id;
  final String targetDeviceId;
  final DeviceCommandType type;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final DeviceCommandStatus status;

  /// Returns a new command with a changed status; the original is untouched.
  DeviceCommand copyWith({DeviceCommandStatus? status}) => DeviceCommand(
        id: id,
        targetDeviceId: targetDeviceId,
        type: type,
        createdAt: createdAt,
        payload: payload,
        status: status ?? this.status,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'targetDeviceId': targetDeviceId,
        'type': type.name,
        'createdAt': createdAt.toIso8601String(),
        'payload': payload,
        'status': status.name,
      };

  factory DeviceCommand.fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Device command id is missing.');
    }
    final Object? targetDeviceId = json['targetDeviceId'];
    if (targetDeviceId is! String || targetDeviceId.isEmpty) {
      throw const FormatException('Device command targetDeviceId is missing.');
    }
    final Object? rawPayload = json['payload'];
    return DeviceCommand(
      id: id,
      targetDeviceId: targetDeviceId,
      type: _parseType(json['type'] as String?),
      createdAt: DateTime.tryParse((json['createdAt'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      payload: rawPayload is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawPayload)
          : <String, dynamic>{},
      status: _parseStatus(json['status'] as String?),
    );
  }

  /// Unknown names are rejected instead of silently changing command intent.
  static DeviceCommandType _parseType(String? value) {
    for (final DeviceCommandType type in DeviceCommandType.values) {
      if (type.name == value) return type;
    }
    throw FormatException('Unknown device command type: $value');
  }

  /// A missing status means a freshly queued command, never a sent one.
  static DeviceCommandStatus _parseStatus(String? value) {
    if (value == null) return DeviceCommandStatus.queued;
    for (final DeviceCommandStatus status in DeviceCommandStatus.values) {
      if (status.name == value) return status;
    }
    throw FormatException('Unknown device command status: $value');
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceCommand &&
      other.id == id &&
      other.targetDeviceId == targetDeviceId &&
      other.type == type &&
      other.createdAt == createdAt &&
      other.status == status &&
      _payloadEquals(other.payload);

  /// Payload length is enough for a consistent hash; equality does the deep
  /// comparison so a JSON round trip still produces an equal value object.
  @override
  int get hashCode =>
      Object.hash(id, targetDeviceId, type, createdAt, status, payload.length);

  bool _payloadEquals(Map<String, dynamic> other) {
    if (payload.length != other.length) return false;
    for (final MapEntry<String, dynamic> entry in payload.entries) {
      if (!other.containsKey(entry.key) ||
          !_valueEquals(entry.value, other[entry.key])) {
        return false;
      }
    }
    return true;
  }

  static bool _valueEquals(Object? left, Object? right) {
    if (left is Map<Object?, Object?> && right is Map<Object?, Object?>) {
      if (left.length != right.length) return false;
      for (final Object? key in left.keys) {
        if (!right.containsKey(key) || !_valueEquals(left[key], right[key])) {
          return false;
        }
      }
      return true;
    }
    if (left is List<Object?> && right is List<Object?>) {
      if (left.length != right.length) return false;
      for (int index = 0; index < left.length; index++) {
        if (!_valueEquals(left[index], right[index])) return false;
      }
      return true;
    }
    return left == right;
  }
}
