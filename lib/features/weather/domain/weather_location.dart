/// A manually configured forecast location.
///
/// AURA never guesses the user's location and never ships a hardcoded city.
/// Coordinates are stored with a user-visible label so the Weather tile can say
/// exactly which place the reading belongs to.
class WeatherLocation {
  const WeatherLocation({
    required this.label,
    required this.latitude,
    required this.longitude,
  });

  static const int schemaVersion = 1;

  final String label;
  final double latitude;
  final double longitude;

  bool get isValid =>
      label.trim().isNotEmpty &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schema': schemaVersion,
        'label': label,
        'latitude': latitude,
        'longitude': longitude,
      };

  /// Returns null for any missing, malformed or out-of-range stored value.
  static WeatherLocation? fromJson(Object? decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final Object? rawSchema = decoded['schema'];
    if (rawSchema is int && rawSchema > schemaVersion) return null;

    final Object? rawLabel = decoded['label'];
    final Object? rawLatitude = decoded['latitude'];
    final Object? rawLongitude = decoded['longitude'];
    if (rawLabel is! String || rawLatitude is! num || rawLongitude is! num) {
      return null;
    }

    final WeatherLocation location = WeatherLocation(
      label: rawLabel.trim(),
      latitude: rawLatitude.toDouble(),
      longitude: rawLongitude.toDouble(),
    );
    return location.isValid ? location : null;
  }

  /// Parses user input. Throws [FormatException] with a readable reason.
  static WeatherLocation parse({
    required String label,
    required String latitude,
    required String longitude,
  }) {
    final String cleanLabel = label.trim();
    if (cleanLabel.isEmpty) {
      throw const FormatException('Enter a name for this location.');
    }
    if (cleanLabel.length > 48) {
      throw const FormatException('Use a shorter location name.');
    }

    final double? lat = _parseNumber(latitude);
    final double? lon = _parseNumber(longitude);
    if (lat == null || lon == null) {
      throw const FormatException('Enter valid numeric coordinates.');
    }
    if (lat < -90 || lat > 90) {
      throw const FormatException('Latitude must be between -90 and 90.');
    }
    if (lon < -180 || lon > 180) {
      throw const FormatException('Longitude must be between -180 and 180.');
    }
    return WeatherLocation(label: cleanLabel, latitude: lat, longitude: lon);
  }

  static double? _parseNumber(String value) => double.tryParse(value.trim());

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WeatherLocation &&
          other.label == label &&
          other.latitude == latitude &&
          other.longitude == longitude;

  @override
  int get hashCode => Object.hash(label, latitude, longitude);
}
