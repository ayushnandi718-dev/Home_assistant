const List<String> _months = <String>[
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

const List<String> _weekdays = <String>[
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

String greetingForHour(int hour) {
  if (hour < 5) return 'Good night';
  if (hour < 12) return 'Good morning';
  if (hour < 17) return 'Good afternoon';
  return 'Good evening';
}

String formatDateHeader(DateTime date) {
  return '${_weekdays[date.weekday - 1]}, ${date.day} ${_months[date.month - 1]}';
}

String formatEventTimestamp(DateTime value) {
  final String day = '${value.day} ${_months[value.month - 1]}';
  final String time = '${value.hour.toString().padLeft(2, '0')}:'
      '${value.minute.toString().padLeft(2, '0')}';
  return '$day - $time';
}

String formatRelativeTime(DateTime value, {DateTime? now}) {
  final DateTime reference = now ?? DateTime.now();
  final Duration delta = reference.difference(value);
  final int minutes = delta.inMinutes;

  if (minutes < 1) return 'just now';
  if (minutes < 60) return '${minutes}m ago';
  final int hours = delta.inHours;
  if (hours < 24) return '${hours}h ago';
  final int days = delta.inDays;
  if (days < 7) return '${days}d ago';
  return formatEventTimestamp(value);
}
