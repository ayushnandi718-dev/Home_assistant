/// AYUSH-only security preferences.
///
/// This model is deliberately separate from global [AppSettings]-style data:
/// it is encrypted at rest with the same DPAPI boundary used by private memory
/// and can never be persisted as plaintext on Windows.
class AyushSecuritySettings {
  const AyushSecuritySettings({
    this.autoLock = AyushAutoLock.fiveMinutes,
    this.backgroundLockGrace = AyushBackgroundLockGrace.thirtySeconds,
  });

  static const AyushSecuritySettings defaults = AyushSecuritySettings();
  static const int schemaVersion = 2;

  final AyushAutoLock autoLock;
  final AyushBackgroundLockGrace backgroundLockGrace;

  bool get isDefault =>
      autoLock == AyushAutoLock.fiveMinutes &&
      backgroundLockGrace == AyushBackgroundLockGrace.thirtySeconds;

  AyushSecuritySettings copyWith({
    AyushAutoLock? autoLock,
    AyushBackgroundLockGrace? backgroundLockGrace,
  }) =>
      AyushSecuritySettings(
        autoLock: autoLock ?? this.autoLock,
        backgroundLockGrace: backgroundLockGrace ?? this.backgroundLockGrace,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schemaVersion,
        'autoLock': autoLock.name,
        'backgroundLockGrace': backgroundLockGrace.name,
      };

  /// Invalid, unknown or future-schema values fall back to the secure default
  /// (5 minutes), never to "Never".
  static AyushSecuritySettings fromJson(Object? value) {
    if (value is! Map<String, dynamic>) return defaults;
    final Object? schema = value['schema'];
    if (schema is int && schema > schemaVersion) return defaults;
    final Object? raw = value['autoLock'];
    final AyushAutoLock autoLock = _parse(
      values: AyushAutoLock.values,
      raw: raw,
      fallback: AyushAutoLock.fiveMinutes,
    );
    // Schema 1 has no background grace. A missing or unknown value falls back
    // to the short secure default; it never inherits the inactivity "Never".
    final Object? rawGrace = value['backgroundLockGrace'];
    final AyushBackgroundLockGrace backgroundLockGrace = _parse(
      values: AyushBackgroundLockGrace.values,
      raw: rawGrace,
      fallback: AyushBackgroundLockGrace.thirtySeconds,
    );
    return AyushSecuritySettings(
      autoLock: autoLock,
      backgroundLockGrace: backgroundLockGrace,
    );
  }

  static T _parse<T extends Enum>({
    required List<T> values,
    required Object? raw,
    required T fallback,
  }) {
    if (raw is! String) return fallback;
    return values.firstWhere(
      (T option) => option.name == raw,
      orElse: () => fallback,
    );
  }

  static bool isValidPayload(Object? value) {
    if (value is! Map<String, dynamic>) return false;
    final Object? schema = value['schema'];
    if (schema is int && schema > schemaVersion) return false;
    // Schema 1 payloads remain valid so they can gain the default grace on
    // migration; future schemas are rejected before any write.
    return value.containsKey('autoLock');
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AyushSecuritySettings &&
          runtimeType == other.runtimeType &&
          other.autoLock == autoLock &&
          other.backgroundLockGrace == backgroundLockGrace;

  @override
  int get hashCode => Object.hash(autoLock, backgroundLockGrace);
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

/// Short grace before AYUSH locks after the app leaves the foreground.
///
/// This is independent of [AyushAutoLock]: selecting inactivity "Never" does
/// not disable the background lock. There is deliberately no "never" option
/// here, so a private workspace cannot stay unlocked in the background.
enum AyushBackgroundLockGrace {
  immediate(Duration.zero, 'Immediately'),
  fifteenSeconds(Duration(seconds: 15), '15 seconds'),
  thirtySeconds(Duration(seconds: 30), '30 seconds'),
  oneMinute(Duration(minutes: 1), '1 minute');

  const AyushBackgroundLockGrace(this.duration, this.label);

  final Duration duration;
  final String label;
}
