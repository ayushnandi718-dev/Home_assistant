/// WMO weather codes grouped into the states the Dashboard can describe.
enum WeatherCondition {
  clear,
  partlyCloudy,
  fog,
  rain,
  snow,
  thunderstorm,
  unknown;

  static WeatherCondition fromCode(int code) => switch (code) {
        0 => WeatherCondition.clear,
        >= 1 && <= 3 => WeatherCondition.partlyCloudy,
        >= 45 && <= 48 => WeatherCondition.fog,
        >= 51 && <= 67 => WeatherCondition.rain,
        >= 71 && <= 77 => WeatherCondition.snow,
        >= 95 => WeatherCondition.thunderstorm,
        _ => WeatherCondition.unknown,
      };

  String get label => switch (this) {
        WeatherCondition.clear => 'Clear sky',
        WeatherCondition.partlyCloudy => 'Partly cloudy',
        WeatherCondition.fog => 'Fog',
        WeatherCondition.rain => 'Rain',
        WeatherCondition.snow => 'Snow',
        WeatherCondition.thunderstorm => 'Thunderstorm',
        WeatherCondition.unknown => 'Condition unavailable',
      };
}

/// One real observation returned by the forecast provider.
class WeatherSnapshot {
  const WeatherSnapshot({
    required this.temperatureCelsius,
    required this.code,
    required this.locationLabel,
    required this.observedAt,
  });

  final double temperatureCelsius;
  final int code;
  final String locationLabel;
  final DateTime observedAt;

  WeatherCondition get condition => WeatherCondition.fromCode(code);

  /// Compact tile value, e.g. `21°`.
  String get temperatureLabel => '${temperatureCelsius.round()}°';
}
