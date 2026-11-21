import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/weather/domain/weather_location.dart';

/// Persists the user's manual forecast location as a small local JSON file.
///
/// A missing, corrupt or future-schema file is treated as "no location", so the
/// Weather tile falls back to its honest set-location state instead of failing.
class WeatherLocationStore {
  WeatherLocationStore({Directory? directory})
      : _directory = directory ?? LocalPaths.appData();

  static const String _fileName = 'weather_location.json';

  final Directory _directory;

  Future<File> _resolvedFile() async {
    await _directory.create(recursive: true);
    return File(
      '${_directory.path}${Platform.pathSeparator}$_fileName',
    );
  }

  Future<WeatherLocation?> load() async {
    try {
      final File file = await _resolvedFile();
      if (!await file.exists()) return null;
      final Object? decoded = jsonDecode(await file.readAsString());
      return WeatherLocation.fromJson(decoded);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(WeatherLocation location) async {
    final File file = await _resolvedFile();
    await file.writeAsString(jsonEncode(location.toJson()), flush: true);
  }

  Future<void> clear() async {
    final File file = await _resolvedFile();
    if (await file.exists()) await file.delete();
  }
}
