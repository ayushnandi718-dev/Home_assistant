/// Features a device may expose once a real transport is implemented.
///
/// This is a contract for FUTURE capability negotiation with a Waveshare
/// ESP32-S3 class device. Hardware has not been ordered and no transport,
/// pairing or connection exists yet. Listing a capability here is NOT a claim
/// that any physical device provides it. Values are only meaningful after a
/// real adapter has negotiated them with actual hardware.
enum DeviceCapability {
  display,
  touch,
  audioOutput,
  microphone,
  led,
  sensors,
  gpio,
  ota,
}

/// Immutable set of negotiated capabilities plus optional version metadata.
///
/// A value object: equality compares contents, not identity. A real transport
/// must create instances only after it has read the versions from hardware.
/// Nothing here invents a device or a capability claim.
class DeviceCapabilities {
  const DeviceCapabilities({
    Set<DeviceCapability> capabilities = const <DeviceCapability>{},
    this.firmwareVersion,
    this.protocolVersion,
  }) : _capabilities = capabilities;

  final Set<DeviceCapability> _capabilities;
  final String? firmwareVersion;
  final String? protocolVersion;

  /// Unmodifiable view so callers cannot mutate a value object after creation.
  Set<DeviceCapability> get capabilities =>
      Set<DeviceCapability>.unmodifiable(_capabilities);

  /// Sorted names give deterministic equality, hashing and JSON output.
  List<String> get _orderedNames {
    final List<String> names = _capabilities
        .map((DeviceCapability capability) => capability.name)
        .toList()
      ..sort();
    return List<String>.unmodifiable(names);
  }

  /// True only when [capability] is present in this explicit contract.
  bool supports(DeviceCapability capability) =>
      _capabilities.contains(capability);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'capabilities': _orderedNames,
        if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
        if (protocolVersion != null) 'protocolVersion': protocolVersion,
      };

  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    final Object? raw = json['capabilities'];
    final Set<DeviceCapability> capabilities = <DeviceCapability>{};
    if (raw is List<Object?>) {
      for (final Object? item in raw) {
        if (item is! String) {
          throw const FormatException(
            'Device capability names must be strings.',
          );
        }
        capabilities.add(_parseCapability(item));
      }
    } else if (raw != null) {
      throw const FormatException('Device capabilities must be a list.');
    }
    return DeviceCapabilities(
      capabilities: capabilities,
      firmwareVersion: json['firmwareVersion'] as String?,
      protocolVersion: json['protocolVersion'] as String?,
    );
  }

  /// Unknown names are rejected instead of silently becoming a capability.
  static DeviceCapability _parseCapability(String value) {
    for (final DeviceCapability capability in DeviceCapability.values) {
      if (capability.name == value) return capability;
    }
    throw FormatException('Unknown device capability: $value');
  }

  @override
  bool operator ==(Object other) {
    if (other is! DeviceCapabilities) return false;
    if (other.firmwareVersion != firmwareVersion ||
        other.protocolVersion != protocolVersion) {
      return false;
    }
    final List<String> mine = _orderedNames;
    final List<String> theirs = other._orderedNames;
    if (mine.length != theirs.length) return false;
    for (int index = 0; index < mine.length; index++) {
      if (mine[index] != theirs[index]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
        Object.hashAll(_orderedNames),
        firmwareVersion,
        protocolVersion,
      );
}
