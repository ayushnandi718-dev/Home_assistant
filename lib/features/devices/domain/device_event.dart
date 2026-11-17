/// Kinds of observation a real device transport may surface.
///
/// This library defines the vocabulary only. It never creates an event, and no
/// event here represents a device or connection that does not physically exist.
enum DeviceEventType { connection, telemetry, error, button }

/// Immutable observation reported by a physical device.
///
/// This is a shape for a future transport, not a sample event. [payload] keys
/// are strings only, and the map is unmodifiable so a value cannot be changed
/// after creation.
class DeviceEvent {
  DeviceEvent({
    required this.id,
    required this.deviceId,
    required this.type,
    required this.timestamp,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) : payload = Map<String, dynamic>.unmodifiable(payload);

  /// Defensive cap used by [DeviceEvent.bounded] for a future transport.
  static const int maxPayloadEntries = 64;

  final String id;
  final String deviceId;
  final DeviceEventType type;
  final DateTime timestamp;
  final Map<String, dynamic> payload;

  /// Creates an event with a payload capped at [maxPayloadEntries] entries.
  ///
  /// Excess entries are dropped, never replaced with placeholder values. This
  /// bound does not create events; it only limits what a real adapter may keep.
  factory DeviceEvent.bounded({
    required String id,
    required String deviceId,
    required DeviceEventType type,
    required DateTime timestamp,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    final Map<String, dynamic> bounded = <String, dynamic>{};
    for (final MapEntry<String, dynamic> entry in payload.entries) {
      if (bounded.length >= maxPayloadEntries) break;
      bounded[entry.key] = entry.value;
    }
    return DeviceEvent(
      id: id,
      deviceId: deviceId,
      type: type,
      timestamp: timestamp,
      payload: bounded,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'deviceId': deviceId,
        'type': type.name,
        'timestamp': timestamp.toIso8601String(),
        'payload': payload,
      };

  factory DeviceEvent.fromJson(Map<String, dynamic> json) {
    final Object? id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('Device event id is missing.');
    }
    final Object? deviceId = json['deviceId'];
    if (deviceId is! String || deviceId.isEmpty) {
      throw const FormatException('Device event deviceId is missing.');
    }
    final Object? rawPayload = json['payload'];
    return DeviceEvent(
      id: id,
      deviceId: deviceId,
      type: _parseType(json['type'] as String?),
      timestamp: DateTime.tryParse((json['timestamp'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      payload: rawPayload is Map<String, dynamic>
          ? Map<String, dynamic>.from(rawPayload)
          : <String, dynamic>{},
    );
  }

  /// Unknown names are rejected so an event is never silently mislabelled.
  static DeviceEventType _parseType(String? value) {
    for (final DeviceEventType type in DeviceEventType.values) {
      if (type.name == value) return type;
    }
    throw FormatException('Unknown device event type: $value');
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceEvent &&
      other.id == id &&
      other.deviceId == deviceId &&
      other.type == type &&
      other.timestamp == timestamp &&
      _payloadEquals(other.payload);

  /// Payload length is enough for a consistent hash; equality does the deep
  /// comparison so a JSON round trip still produces an equal value object.
  @override
  int get hashCode =>
      Object.hash(id, deviceId, type, timestamp, payload.length);

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
