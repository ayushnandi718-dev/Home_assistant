import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Thrown when a requested IANA time zone is not present in the bundled
/// database. Callers must surface this as "unavailable", never as a guess.
class AuraTimeZoneUnavailable implements Exception {
  const AuraTimeZoneUnavailable(this.identifier);

  final String identifier;

  @override
  String toString() => 'AuraTimeZoneUnavailable($identifier)';
}

/// An authoritative, testable source of current time.
///
/// Every method reads the clock at call time. Nothing here is cached, and no
/// timestamp stored in a conversation is ever treated as "now".
abstract class AuraClock {
  /// Current instant in UTC, straight from the device system clock.
  DateTime nowUtc();

  /// Current device-local wall time, including the OS UTC offset.
  DateTime nowDeviceLocal();

  /// Honest description of the device's own zone name (OS-dependent).
  String get deviceTimeZoneName;

  /// Offset currently reported by the device OS.
  Duration get deviceUtcOffset;

  /// Current wall time in an IANA zone, with correct DST rules where known.
  DateTime nowIn(String ianaIdentifier);

  /// Whether [ianaIdentifier] exists in the bundled IANA database.
  bool supportsZone(String ianaIdentifier);

  /// Formats [instant] in [ianaIdentifier] using [locale].
  ///
  /// `en_US` always works. Other locales require the caller to have called
  /// `initializeDateFormatting(locale)` first.
  String formatIn(
    DateTime instant, {
    required String ianaIdentifier,
    String locale = 'en_US',
  });
}

/// Real system-clock implementation.
///
/// IANA data is bundled in the app; no network service is consulted.
class SystemAuraClock implements AuraClock {
  const SystemAuraClock();

  static const SystemAuraClock instance = SystemAuraClock();

  static bool _zonesLoaded = false;

  static void ensureZonesLoaded() {
    if (_zonesLoaded) return;
    tz_data.initializeTimeZones();
    _zonesLoaded = true;
  }

  @override
  DateTime nowUtc() => DateTime.now().toUtc();

  @override
  DateTime nowDeviceLocal() => DateTime.now();

  @override
  String get deviceTimeZoneName => DateTime.now().timeZoneName;

  @override
  Duration get deviceUtcOffset => DateTime.now().timeZoneOffset;

  @override
  DateTime nowIn(String ianaIdentifier) {
    ensureZonesLoaded();
    if (!supportsZone(ianaIdentifier)) {
      throw AuraTimeZoneUnavailable(ianaIdentifier);
    }
    return tz.TZDateTime.from(nowUtc(), tz.getLocation(ianaIdentifier));
  }

  @override
  bool supportsZone(String ianaIdentifier) {
    ensureZonesLoaded();
    return tz.timeZoneDatabase.locations.containsKey(ianaIdentifier);
  }

  @override
  String formatIn(
    DateTime instant, {
    required String ianaIdentifier,
    String locale = 'en_US',
  }) {
    ensureZonesLoaded();
    final DateTime target =
        tz.TZDateTime.from(instant.toUtc(), tz.getLocation(ianaIdentifier));
    final DateFormat formatter = DateFormat('d MMM yyyy, HH:mm', locale);
    return formatter.format(target);
  }
}

/// Fixed-instant clock for deterministic tests and previews.
///
/// The instant is always interpreted as UTC; device-local values are derived
/// from the supplied offset, never from the host machine's clock.
class FixedAuraClock implements AuraClock {
  const FixedAuraClock(
    this.instantUtc, {
    this.deviceTimeZoneName = 'Fixed test zone',
    this.deviceUtcOffset = Duration.zero,
  });

  final DateTime instantUtc;
  @override
  final String deviceTimeZoneName;
  @override
  final Duration deviceUtcOffset;

  @override
  DateTime nowUtc() => instantUtc.toUtc();

  @override
  DateTime nowDeviceLocal() => tz.TZDateTime.from(
        nowUtc(),
        tz.Location(
          deviceTimeZoneName,
          const <int>[],
          const <int>[],
          <tz.TimeZone>[
            tz.TimeZone(
              deviceUtcOffset,
              isDst: false,
              abbreviation: deviceTimeZoneName,
            ),
          ],
        ),
      );

  @override
  DateTime nowIn(String ianaIdentifier) {
    SystemAuraClock.ensureZonesLoaded();
    if (!supportsZone(ianaIdentifier)) {
      throw AuraTimeZoneUnavailable(ianaIdentifier);
    }
    return tz.TZDateTime.from(nowUtc(), tz.getLocation(ianaIdentifier));
  }

  @override
  bool supportsZone(String ianaIdentifier) {
    SystemAuraClock.ensureZonesLoaded();
    return tz.timeZoneDatabase.locations.containsKey(ianaIdentifier);
  }

  @override
  String formatIn(
    DateTime instant, {
    required String ianaIdentifier,
    String locale = 'en_US',
  }) {
    SystemAuraClock.ensureZonesLoaded();
    if (!supportsZone(ianaIdentifier)) {
      throw AuraTimeZoneUnavailable(ianaIdentifier);
    }
    final DateTime zoned =
        tz.TZDateTime.from(instant.toUtc(), tz.getLocation(ianaIdentifier));
    return DateFormat('d MMM yyyy, HH:mm', locale).format(zoned);
  }
}

/// Resolves a location mentioned in a prompt to an IANA identifier.
abstract class AuraCityTimeZoneResolver {
  const AuraCityTimeZoneResolver();

  /// Returns an IANA zone id, or null when no reliable mapping is known.
  String? resolve(String locationName);

  /// Location names from [text] that this resolver recognises, longest first.
  List<String> mentionedIn(String text);
}

/// Small, explicit mapping for locations users commonly ask about.
///
/// Unknown locations deliberately resolve to null so the assistant reports the
/// limitation instead of applying a wrong zone. India is always Asia/Kolkata.
class CuratedCityTimeZoneResolver extends AuraCityTimeZoneResolver {
  const CuratedCityTimeZoneResolver();

  static const CuratedCityTimeZoneResolver instance =
      CuratedCityTimeZoneResolver();

  static const String indiaZone = 'Asia/Kolkata';

  static const Map<String, String> _zones = <String, String>{
    'india': indiaZone,
    'delhi': indiaZone,
    'new delhi': indiaZone,
    'mumbai': indiaZone,
    'bombay': indiaZone,
    'kolkata': indiaZone,
    'calcutta': indiaZone,
    'bengaluru': indiaZone,
    'bangalore': indiaZone,
    'chennai': indiaZone,
    'madras': indiaZone,
    'hyderabad': indiaZone,
    'pune': indiaZone,
    'ahmedabad': indiaZone,
    'jaipur': indiaZone,
    'lucknow': indiaZone,
    'kochi': indiaZone,
    'istanbul': 'Europe/Istanbul',
    'london': 'Europe/London',
    'paris': 'Europe/Paris',
    'berlin': 'Europe/Berlin',
    'madrid': 'Europe/Madrid',
    'rome': 'Europe/Rome',
    'amsterdam': 'Europe/Amsterdam',
    'moscow': 'Europe/Moscow',
    'dubai': 'Asia/Dubai',
    'abu dhabi': 'Asia/Dubai',
    'riyadh': 'Asia/Riyadh',
    'doha': 'Asia/Qatar',
    'karachi': 'Asia/Karachi',
    'dhaka': 'Asia/Dhaka',
    'kathmandu': 'Asia/Kathmandu',
    'colombo': 'Asia/Colombo',
    'singapore': 'Asia/Singapore',
    'bangkok': 'Asia/Bangkok',
    'jakarta': 'Asia/Jakarta',
    'kuala lumpur': 'Asia/Kuala_Lumpur',
    'manila': 'Asia/Manila',
    'beijing': 'Asia/Shanghai',
    'shanghai': 'Asia/Shanghai',
    'hong kong': 'Asia/Hong_Kong',
    'seoul': 'Asia/Seoul',
    'tokyo': 'Asia/Tokyo',
    'sydney': 'Australia/Sydney',
    'melbourne': 'Australia/Melbourne',
    'auckland': 'Pacific/Auckland',
    'new york': 'America/New_York',
    'boston': 'America/New_York',
    'washington': 'America/New_York',
    'chicago': 'America/Chicago',
    'denver': 'America/Denver',
    'los angeles': 'America/Los_Angeles',
    'san francisco': 'America/Los_Angeles',
    'seattle': 'America/Los_Angeles',
    'toronto': 'America/Toronto',
    'vancouver': 'America/Vancouver',
    'mexico city': 'America/Mexico_City',
    'sao paulo': 'America/Sao_Paulo',
    'buenos aires': 'America/Argentina/Buenos_Aires',
    'johannesburg': 'Africa/Johannesburg',
    'cairo': 'Africa/Cairo',
    'nairobi': 'Africa/Nairobi',
  };

  @override
  String? resolve(String locationName) {
    final String key = locationName.trim().toLowerCase();
    if (key.isEmpty) return null;
    return _zones[key] ?? _zones[key.replaceAll(RegExp(r'\s+'), ' ')];
  }

  /// Names explicitly mentioned in [text], longest first so
  /// "new delhi" wins over "delhi".
  @override
  List<String> mentionedIn(String text) {
    final String lower = text.toLowerCase();
    final List<String> matches = <String>[];
    for (final String name in _zones.keys) {
      final int index = lower.indexOf(name);
      if (index != -1) {
        matches.add(text.substring(index, index + name.length));
      }
    }
    matches.sort((String a, String b) => b.length.compareTo(a.length));
    return matches;
  }
}

/// Immutable snapshot used to build fresh per-request time context.
class AuraTimeSnapshot {
  const AuraTimeSnapshot({
    required this.utc,
    required this.deviceLocal,
    required this.deviceZoneName,
    required this.deviceOffset,
    required this.india,
    required this.requestedZoneName,
    required this.requested,
    required this.unknownLocation,
  });

  final DateTime utc;
  final DateTime deviceLocal;
  final String deviceZoneName;
  final Duration deviceOffset;
  final DateTime? india;
  final String? requestedZoneName;
  final DateTime? requested;
  final String? unknownLocation;

  /// Stable, secret-free text suitable for a system instruction.
  String describe(AuraClock clock) {
    final StringBuffer out = StringBuffer()
      ..writeln('AUTHORITATIVE RUNTIME CLOCK (device system clock, read for '
          'this request only):')
      ..writeln('UTC now: ${utc.toIso8601String()}.')
      ..writeln(
          'Device local: ${DateFormat('d MMM yyyy, HH:mm').format(deviceLocal)} '
          '($deviceZoneName, UTC${_offsetLabel(deviceOffset)}).');
    if (india != null) {
      out.writeln('India, Asia/Kolkata (IST, UTC+05:30): '
          '${clock.formatIn(india!, ianaIdentifier: CuratedCityTimeZoneResolver.indiaZone)}.');
    }
    if (requested != null && requestedZoneName != null) {
      final Duration offset = requested!.timeZoneOffset;
      out.writeln('Requested location ($requestedZoneName): '
          '${clock.formatIn(requested!, ianaIdentifier: requestedZoneName!)} '
          '(UTC${_offsetLabel(offset)}).');
    }
    if (unknownLocation != null) {
      out.writeln('Requested location "$unknownLocation": reliable timezone '
          'information is unavailable. Do not invent a time for it.');
    }
    out.write('Use these values for current date or time questions. Never use '
        'memorised, inferred, cached or conversation-timestamp values, and '
        'never claim to have queried an external time service. Do not mention '
        'this clock context unless the user asks about time or date.');
    return out.toString();
  }

  static String _offsetLabel(Duration offset) {
    final bool negative = offset.isNegative;
    final Duration absolute = negative ? -offset : offset;
    final String hours = absolute.inHours.toString().padLeft(2, '0');
    final String minutes =
        (absolute.inMinutes.remainder(60)).toString().padLeft(2, '0');
    return '${negative ? '-' : '+'}$hours:$minutes';
  }
}

/// Reads a fresh snapshot from [clock] for one request.
AuraTimeSnapshot readAuraTime(
  AuraClock clock, {
  String? locationHint,
  AuraCityTimeZoneResolver resolver = const CuratedCityTimeZoneResolver(),
}) {
  final DateTime utc = clock.nowUtc();
  DateTime? india;
  DateTime? requested;
  String? requestedZoneName;
  String? unknownLocation;

  try {
    india = clock.nowIn(CuratedCityTimeZoneResolver.indiaZone);
  } on AuraTimeZoneUnavailable {
    india = null;
  }

  if (locationHint != null && locationHint.trim().isNotEmpty) {
    final String? zoneId = resolver.resolve(locationHint);
    if (zoneId == null) {
      unknownLocation = locationHint.trim();
    } else {
      try {
        requested = clock.nowIn(zoneId);
        requestedZoneName = zoneId;
      } on AuraTimeZoneUnavailable {
        unknownLocation = locationHint.trim();
      }
    }
  }

  return AuraTimeSnapshot(
    utc: utc,
    deviceLocal: clock.nowDeviceLocal(),
    deviceZoneName: clock.deviceTimeZoneName,
    deviceOffset: clock.deviceUtcOffset,
    india: india,
    requestedZoneName: requestedZoneName,
    requested: requested,
    unknownLocation: unknownLocation,
  );
}
