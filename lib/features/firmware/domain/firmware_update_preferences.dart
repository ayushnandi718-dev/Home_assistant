/// Release channel preference for a future firmware release service.
///
/// This is configuration only. No release is fetched, downloaded or installed
/// by this build, and selecting a channel never contacts a device or a server.
enum FirmwareChannel { stable, beta }

extension FirmwareChannelX on FirmwareChannel {
  String get label => switch (this) {
        FirmwareChannel.stable => 'Stable',
        FirmwareChannel.beta => 'Beta',
      };

  String get description => switch (this) {
        FirmwareChannel.stable => 'Validated releases only.',
        FirmwareChannel.beta => 'Pre-release builds; may be incomplete.',
      };
}

/// Locally saved preferences for a future firmware update flow.
///
/// Every field is workspace-scoped configuration that a real, authenticated
/// release service and device transport could consume in a future build. This
/// class never claims that an update was checked, verified or installed.
class FirmwareUpdatePreferences {
  const FirmwareUpdatePreferences({
    this.channel = FirmwareChannel.stable,
    this.autoCheckEnabled = false,
    this.requireVerification = true,
  });

  static const FirmwareUpdatePreferences defaults = FirmwareUpdatePreferences();

  final FirmwareChannel channel;
  final bool autoCheckEnabled;
  final bool requireVerification;

  FirmwareUpdatePreferences copyWith({
    FirmwareChannel? channel,
    bool? autoCheckEnabled,
    bool? requireVerification,
  }) =>
      FirmwareUpdatePreferences(
        channel: channel ?? this.channel,
        autoCheckEnabled: autoCheckEnabled ?? this.autoCheckEnabled,
        requireVerification: requireVerification ?? this.requireVerification,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'version': 1,
        'channel': channel.name,
        'autoCheckEnabled': autoCheckEnabled,
        'requireVerification': requireVerification,
      };

  factory FirmwareUpdatePreferences.fromJson(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return defaults;
    return FirmwareUpdatePreferences(
      channel: _enumByName<FirmwareChannel>(
        FirmwareChannel.values,
        decoded['channel'],
        defaults.channel,
      ),
      // Missing or malformed booleans fall back to the conservative default.
      autoCheckEnabled: decoded['autoCheckEnabled'] == true,
      requireVerification: decoded['requireVerification'] != false,
    );
  }

  static T _enumByName<T extends Enum>(
    Iterable<T> values,
    Object? name,
    T fallback,
  ) {
    if (name is! String) return fallback;
    for (final T value in values) {
      if (value.name == name) return value;
    }
    return fallback;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FirmwareUpdatePreferences &&
          other.channel == channel &&
          other.autoCheckEnabled == autoCheckEnabled &&
          other.requireVerification == requireVerification;

  @override
  int get hashCode =>
      Object.hash(channel, autoCheckEnabled, requireVerification);
}
