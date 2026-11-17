import 'package:aura_hub/features/devices/domain/device_capability.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';

/// Point-in-time status of one physical device, reported by a real source.
///
/// Nothing creates an instance by itself: a future transport fills this only
/// after reading an actual device. The existing [DeviceLinkState] is reused so
/// connection semantics stay consistent with the rest of the Devices feature.
class DeviceStatusSnapshot {
  const DeviceStatusSnapshot({
    required this.deviceId,
    required this.connection,
    this.capabilities,
    required this.lastUpdated,
  });

  final String deviceId;
  final DeviceLinkState connection;
  final DeviceCapabilities? capabilities;
  final DateTime lastUpdated;

  bool get isConnected => connection.isConnected;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'deviceId': deviceId,
        'connection': _connectionToJson(connection),
        if (capabilities != null) 'capabilities': capabilities!.toJson(),
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  factory DeviceStatusSnapshot.fromJson(Map<String, dynamic> json) {
    final Object? deviceId = json['deviceId'];
    if (deviceId is! String || deviceId.isEmpty) {
      throw const FormatException('Device status deviceId is missing.');
    }
    final Object? rawConnection = json['connection'];
    final Object? rawCapabilities = json['capabilities'];
    return DeviceStatusSnapshot(
      deviceId: deviceId,
      connection: rawConnection is Map<String, dynamic>
          ? _connectionFromJson(rawConnection)
          : const DeviceLinkState(),
      capabilities: rawCapabilities is Map<String, dynamic>
          ? DeviceCapabilities.fromJson(rawCapabilities)
          : null,
      lastUpdated: DateTime.tryParse((json['lastUpdated'] as String?) ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  static Map<String, dynamic> _connectionToJson(DeviceLinkState link) =>
      <String, dynamic>{
        'status': link.status.name,
        if (link.deviceId != null) 'deviceId': link.deviceId,
        if (link.message != null) 'message': link.message,
        if (link.changedAt != null)
          'changedAt': link.changedAt!.toIso8601String(),
      };

  static DeviceLinkState _connectionFromJson(Map<String, dynamic> json) {
    final String? name = json['status'] as String?;
    final DeviceLinkStatus status = DeviceLinkStatus.values.firstWhere(
      (DeviceLinkStatus item) => item.name == name,
      orElse: () => DeviceLinkStatus.notPaired,
    );
    return DeviceLinkState(
      status: status,
      deviceId: json['deviceId'] as String?,
      message: json['message'] as String?,
      changedAt: DateTime.tryParse((json['changedAt'] as String?) ?? ''),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is DeviceStatusSnapshot &&
      other.deviceId == deviceId &&
      other.connection.status == connection.status &&
      other.connection.deviceId == connection.deviceId &&
      other.connection.message == connection.message &&
      other.connection.changedAt == connection.changedAt &&
      other.lastUpdated == lastUpdated &&
      other.capabilities == capabilities;

  @override
  int get hashCode => Object.hash(
        deviceId,
        connection.status,
        connection.deviceId,
        connection.message,
        connection.changedAt,
        capabilities,
        lastUpdated,
      );
}

/// Boundary for a future transport that reports real device status changes.
///
/// There is deliberately no fake implementation here: an empty status stream
/// would be indistinguishable from a device that exists but is silent.
abstract class DeviceStatusSource {
  Stream<DeviceStatusSnapshot> get status;
}
