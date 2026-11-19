/// AYUSH-only security preferences.
///
/// This model is deliberately separate from global [AppSettings]-style data:
/// it is encrypted at rest with the same DPAPI boundary used by private memory
/// and can never be persisted as plaintext on Windows.
class AyushSecuritySettings {
  const AyushSecuritySettings({
    this.autoLock = AyushAutoLock.fiveMinutes,
  });

  static const AyushSecuritySettings defaults = AyushSecuritySettings();
  static const int schemaVersion = 1;

  final AyushAutoLock autoLock;

  bool get isDefault => autoLock == AyushAutoLock.fiveMinutes;

  AyushSecuritySettings copyWith({AyushAutoLock? autoLock}) =>
      AyushSecuritySettings(autoLock: autoLock ?? this.autoLock);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schemaVersion,
        'autoLock': autoLock.name,
      };

  /// Invalid, unknown or future-schema values fall back to the secure default
  /// (5 minutes), never to "Never".
  static AyushSecuritySettings fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return defaults;
    final Object? schema = value['schema'];
    if (schema is int && schema > schemaVersion) return defaults;
    final Object? raw = value['autoLock'];
    final AyushAutoLock autoLock = raw is String
        ? AyushAutoLock.values.firstWhere(
            (AyushAutoLock option) => option.name == raw,
            orElse: () => AyushAutoLock.fiveMinutes,
          )
        : AyushAutoLock.fiveMinutes;
    return AyushSecuritySettings(autoLock: autoLock);
  }

  static bool isValidPayload(Object? value) {
    if (value is! Map<String, dynamic>) return false;
    final Object? schema = value['schema'];
    if (schema is int && schema > schemaVersion) return false;
    return value.containsKey('autoLock');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AyushSecuritySettings &&
          runtimeType == other.runtimeType &&
          other.autoLock == autoLock;

  @override
  int get hashCode => autoLock.hashCode;
}

/// Inactivity interval before AYUSH locks itself.
///
/// "Never" is an explicit user choice, not a corruption fallback.
enum AyushAutoLock {
  never(0, 'Never'),
  oneMinute(1, '1 minute'),
  fiveMinutes(5, '5 minutes'),
  tenMinutes(10, '10 minutes'),
  fifteenMinutes(15, '15 minutes'),
  thirtyMinutes(30, '30 minutes');

  const AyushAutoLock(this.minutes, this.label);

  final int minutes;
  final String label;

  Duration? get duration => minutes == 0 ? null : Duration(minutes: minutes);
}
