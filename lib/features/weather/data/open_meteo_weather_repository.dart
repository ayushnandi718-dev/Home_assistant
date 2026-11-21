import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:aura_hub/features/weather/domain/weather_location.dart';
import 'package:aura_hub/features/weather/domain/weather_repository.dart';
import 'package:aura_hub/features/weather/domain/weather_snapshot.dart';

/// Free Open-Meteo current-conditions endpoint. No key or paid service.
class OpenMeteoWeatherRepository implements WeatherRepository {
  OpenMeteoWeatherRepository({
    http.Client? client,
    this.timeout = const Duration(seconds: 8),
  }) : _injectedClient = client;

  static const String endpoint = 'https://api.open-meteo.com/v1/forecast';

  final http.Client? _injectedClient;
  http.Client? _ownedClient;
  final Duration timeout;

  http.Client get _client =>
      _injectedClient ?? (_ownedClient ??= http.Client());

  @override
  Future<WeatherSnapshot> fetchCurrent(WeatherLocation location) async {
    final Uri uri = Uri.parse(endpoint).replace(
      queryParameters: <String, String>{
        'latitude': location.latitude.toStringAsFixed(4),
        'longitude': location.longitude.toStringAsFixed(4),
        'current': 'temperature_2m,weather_code',
      },
    );

    try {
      final http.Response response = await _client.get(uri).timeout(timeout);
      if (response.statusCode != 200) {
        throw WeatherFetchException(
          'Weather service returned ${response.statusCode}.',
        );
      }

      final Object? decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const WeatherFetchException('Weather response was malformed.');
      }
      final Object? current = decoded['current'];
      if (current is! Map<String, dynamic>) {
        throw const WeatherFetchException(
            'Weather response had no current data.');
      }
      final Object? temperature = current['temperature_2m'];
      final Object? code = current['weather_code'];
      if (temperature is! num || code is! num) {
        throw const WeatherFetchException('Weather values were incomplete.');
      }

      final DateTime? observedAt =
          DateTime.tryParse(current['time'] as String? ?? '');
      return WeatherSnapshot(
        temperatureCelsius: temperature.toDouble(),
        code: code.round(),
        locationLabel: location.label,
        observedAt: observedAt ?? DateTime.now(),
      );
    } on WeatherFetchException {
      rethrow;
    } on TimeoutException {
      throw const WeatherFetchException('Weather request timed out.');
    } on FormatException {
      throw const WeatherFetchException('Weather response was malformed.');
    } on Object catch (error) {
      throw WeatherFetchException('Weather request failed: $error');
    }
  }
}
