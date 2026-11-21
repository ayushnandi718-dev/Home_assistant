import 'package:aura_hub/features/weather/domain/weather_location.dart';
import 'package:aura_hub/features/weather/domain/weather_snapshot.dart';

/// Failure with a short, user-safe reason. Raw response bodies and coordinates
/// are never surfaced in the Dashboard.
class WeatherFetchException implements Exception {
  const WeatherFetchException(this.message);

  final String message;

  @override
  String toString() => 'WeatherFetchException($message)';
}

/// Transport-independent weather source. Tests inject a fake implementation so
/// no widget test needs network access.
abstract class WeatherRepository {
  const WeatherRepository();

  Future<WeatherSnapshot> fetchCurrent(WeatherLocation location);
}
