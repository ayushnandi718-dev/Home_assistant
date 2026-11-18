import 'package:aura_hub/features/family/domain/family_member.dart';

/// One upcoming birthday resolved from a saved full birth date.
class FamilyBirthday {
  const FamilyBirthday({
    required this.member,
    required this.nextOccurrence,
    required this.daysAway,
    required this.turningAge,
  });

  final FamilyMember member;
  final DateTime nextOccurrence;
  final int daysAway;
  final int? turningAge;

  bool get isToday => daysAway == 0;

  String get description {
    final String date = FamilyBirthdayService.formatDate(nextOccurrence);
    final String age = turningAge == null ? '' : ' · turning $turningAge';
    if (isToday) return 'Today$age';
    if (daysAway == 1) return 'Tomorrow$age';
    return '$date · $daysAway days away$age';
  }
}

/// Date-aware birthday helpers with an explicit February 29 policy.
///
/// A person born on February 29 is celebrated on February 28 in non-leap
/// years. The saved birth date is never changed.
abstract final class FamilyBirthdayService {
  static const List<String> months = <String>[
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static String formatDate(DateTime date) =>
      '${date.day} ${months[date.month - 1]}';

  static DateTime dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static int daysBetween(DateTime from, DateTime to) {
    final DateTime start = DateTime.utc(from.year, from.month, from.day);
    final DateTime end = DateTime.utc(to.year, to.month, to.day);
    return end.difference(start).inDays;
  }

  /// Returns the next birthday on or after [now].
  static DateTime? nextOccurrence(
    DateTime birthDate, {
    DateTime? now,
  }) {
    final DateTime today = dateOnly(now ?? DateTime.now());
    final DateTime anniversary = _anniversaryIn(birthDate, today.year);
    if (!anniversary.isBefore(today)) return anniversary;
    return _anniversaryIn(birthDate, today.year + 1);
  }

  static DateTime _anniversaryIn(DateTime birthDate, int year) {
    if (birthDate.month == 2 && birthDate.day == 29) {
      final bool leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0);
      return DateTime(year, 2, leap ? 29 : 28);
    }
    return DateTime(year, birthDate.month, birthDate.day);
  }

  /// Age reached on [date]. Null when the full birth date is unavailable.
  static int? ageOn(DateTime birthDate, DateTime date) {
    final DateTime birthday = _anniversaryIn(birthDate, date.year);
    if (date.isBefore(birthday)) return date.year - birthDate.year - 1;
    return date.year - birthDate.year;
  }

  static List<FamilyBirthday> upcoming(
    List<FamilyMember> members, {
    DateTime? now,
    int limit = 5,
  }) {
    final DateTime reference = now ?? DateTime.now();
    final List<FamilyBirthday> result = <FamilyBirthday>[];
    for (final FamilyMember member in members) {
      final DateTime? birthDate = member.dateOfBirth;
      if (birthDate == null) continue;
      final DateTime? next = nextOccurrence(birthDate, now: reference);
      if (next == null) continue;
      result.add(
        FamilyBirthday(
          member: member,
          nextOccurrence: next,
          daysAway: daysBetween(reference, next),
          turningAge: ageOn(birthDate, next),
        ),
      );
    }
    result.sort((FamilyBirthday a, FamilyBirthday b) {
      final int byDate = a.nextOccurrence.compareTo(b.nextOccurrence);
      if (byDate != 0) return byDate;
      return a.member.displayName.compareTo(b.member.displayName);
    });
    return limit <= 0 ? result : result.take(limit).toList(growable: false);
  }
}
