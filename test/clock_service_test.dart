import 'package:aura_hub/core/services/clock_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

void main() {
  SystemAuraClock.ensureZonesLoaded();

  group('FixedAuraClock', () {
    test('converts a fixed UTC instant to India Standard Time', () {
      final AuraClock clock = FixedAuraClock(DateTime.utc(2026, 1, 15, 10, 30));

      final DateTime ist = clock.nowIn(CuratedCityTimeZoneResolver.indiaZone);

      expect(ist.hour, 16);
      expect(ist.minute, 0);
      expect(ist.timeZoneOffset, const Duration(hours: 5, minutes: 30));
      expect(
        clock.formatIn(ist,
            ianaIdentifier: CuratedCityTimeZoneResolver.indiaZone),
        contains('16:00'),
      );
      expect(clock.nowUtc(), DateTime.utc(2026, 1, 15, 10, 30));
    });

    test('derives device-local time from the injected offset only', () {
      final AuraClock clock = FixedAuraClock(
        DateTime.utc(2026, 1, 15, 10, 30),
        deviceTimeZoneName: 'Fixed EST',
        deviceUtcOffset: Duration(hours: -5),
      );

      final DateTime local = clock.nowDeviceLocal();

      expect(local.hour, 5);
      expect(local.minute, 30);
      expect(local.timeZoneOffset, const Duration(hours: -5));
      expect(clock.deviceTimeZoneName, 'Fixed EST');
      expect(clock.deviceUtcOffset, const Duration(hours: -5));
    });

    test('handles midnight date rollover', () {
      final AuraClock clock = FixedAuraClock(DateTime.utc(2026, 1, 15, 18, 30));

      final DateTime ist = clock.nowIn(CuratedCityTimeZoneResolver.indiaZone);

      expect(ist.day, 16);
      expect(ist.hour, 0);
      expect(ist.minute, 0);
    });

    test('applies different zones and DST offsets correctly', () {
      final AuraClock summer = FixedAuraClock(DateTime.utc(2026, 7, 1, 12));
      final AuraClock winter = FixedAuraClock(DateTime.utc(2026, 1, 15, 12));

      expect(
        summer.nowIn('Europe/London').timeZoneOffset,
        const Duration(hours: 1),
      );
      expect(
        summer.nowIn('America/New_York').timeZoneOffset,
        const Duration(hours: -4),
      );
      expect(
        winter.nowIn('Europe/London').timeZoneOffset,
        Duration.zero,
      );
      expect(
        winter.nowIn('America/New_York').timeZoneOffset,
        const Duration(hours: -5),
      );
      expect(summer.nowIn('Asia/Tokyo').hour, 21);
    });

    test('throws for an unknown IANA zone instead of guessing', () {
      final AuraClock clock = FixedAuraClock(DateTime.utc(2026, 1, 15, 10));

      expect(
        () => clock.nowIn('Not/AZone'),
        throwsA(isA<AuraTimeZoneUnavailable>()),
      );
      expect(clock.supportsZone('Not/AZone'), isFalse);
    });
  });

  group('location resolution', () {
    const CuratedCityTimeZoneResolver resolver = CuratedCityTimeZoneResolver();

    test('India is always mapped to Asia/Kolkata', () {
      expect(resolver.resolve('india'), 'Asia/Kolkata');
      expect(resolver.resolve('New Delhi'), 'Asia/Kolkata');
      expect(resolver.resolve('MUMBAI'), 'Asia/Kolkata');
      expect(resolver.resolve('Bengaluru'), 'Asia/Kolkata');
    });

    test('longer city names win and unknown locations stay unresolved', () {
      expect(resolver.mentionedIn('time in New Delhi').first, 'New Delhi');
      expect(resolver.resolve('Atlantis'), isNull);
      expect(resolver.resolve(''), isNull);
    });
  });

  group('readAuraTime', () {
    test('reads a fresh value for every call', () {
      final _SteppingClock clock = _SteppingClock(
        DateTime.utc(2026, 1, 15, 10, 30),
      );

      final AuraTimeSnapshot first = readAuraTime(clock);
      clock.advance(const Duration(hours: 2));
      final AuraTimeSnapshot second = readAuraTime(clock);

      expect(first.utc, DateTime.utc(2026, 1, 15, 10, 30));
      expect(second.utc, DateTime.utc(2026, 1, 15, 12, 30));
      expect(first.istHour, 16);
      expect(second.istHour, 18);
    });

    test('includes the requested city zone rather than the device zone', () {
      final AuraClock clock = FixedAuraClock(DateTime.utc(2026, 7, 1, 12));

      final AuraTimeSnapshot snapshot = readAuraTime(
        clock,
        locationHint: 'London',
      );

      expect(snapshot.requestedZoneName, 'Europe/London');
      expect(snapshot.requested?.hour, 13);
      expect(snapshot.requested?.timeZoneOffset, const Duration(hours: 1));
      expect(snapshot.india?.hour, 17);
    });

    test('reports unavailable zone information honestly', () {
      final AuraClock clock = FixedAuraClock(DateTime.utc(2026, 1, 15, 10));

      final AuraTimeSnapshot snapshot = readAuraTime(
        clock,
        locationHint: 'Atlantis',
      );

      expect(snapshot.unknownLocation, 'Atlantis');
      expect(snapshot.requested, isNull);
      expect(snapshot.describe(clock), contains('reliable timezone'));
      expect(snapshot.describe(clock), contains('Do not invent a time'));
    });

    test('does not fail when the India zone itself is unavailable', () {
      final _IndiaUnavailableClock clock = _IndiaUnavailableClock(
        DateTime.utc(2026, 1, 15, 10),
      );

      final AuraTimeSnapshot snapshot = readAuraTime(clock);

      expect(snapshot.india, isNull);
      expect(snapshot.describe(clock), isNot(contains('Asia/Kolkata')));
      expect(snapshot.utc, DateTime.utc(2026, 1, 15, 10));
    });
  });
}

extension on AuraTimeSnapshot {
  int get istHour => india?.hour ?? -1;
}

class _SteppingClock implements AuraClock {
  _SteppingClock(this._instant);

  DateTime _instant;

  void advance(Duration duration) => _instant = _instant.add(duration);

  @override
  DateTime nowUtc() => _instant.toUtc();

  @override
  DateTime nowDeviceLocal() => _instant;

  @override
  String get deviceTimeZoneName => 'Stepping test zone';

  @override
  Duration get deviceUtcOffset => Duration.zero;

  @override
  DateTime nowIn(String ianaIdentifier) =>
      tz.TZDateTime.from(nowUtc(), tz.getLocation(ianaIdentifier));

  @override
  bool supportsZone(String ianaIdentifier) =>
      tz.timeZoneDatabase.locations.containsKey(ianaIdentifier);

  @override
  String formatIn(
    DateTime instant, {
    required String ianaIdentifier,
    String locale = 'en_US',
  }) {
    return DateFormat('d MMM yyyy, HH:mm', locale).format(
      tz.TZDateTime.from(instant.toUtc(), tz.getLocation(ianaIdentifier)),
    );
  }
}

class _IndiaUnavailableClock extends FixedAuraClock {
  _IndiaUnavailableClock(super.instantUtc);

  @override
  DateTime nowIn(String ianaIdentifier) {
    if (ianaIdentifier == CuratedCityTimeZoneResolver.indiaZone) {
      throw AuraTimeZoneUnavailable(ianaIdentifier);
    }
    return super.nowIn(ianaIdentifier);
  }
}
