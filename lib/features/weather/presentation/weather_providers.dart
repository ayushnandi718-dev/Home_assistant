import 'dart:async';

import 'package:aura_hub/features/weather/data/open_meteo_weather_repository.dart';
import 'package:aura_hub/features/weather/data/weather_location_store.dart';
import 'package:aura_hub/features/weather/domain/weather_location.dart';
import 'package:aura_hub/features/weather/domain/weather_repository.dart';
import 'package:aura_hub/features/weather/domain/weather_snapshot.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<WeatherRepository> weatherRepositoryProvider =
    Provider<WeatherRepository>((Ref ref) {
  return OpenMeteoWeatherRepository();
});

final Provider<WeatherLocationStore> weatherLocationStoreProvider =
    Provider<WeatherLocationStore>((Ref ref) => WeatherLocationStore());

/// Loads/saves the manual location. No location is ever invented by the app.
class WeatherLocationController extends StateNotifier<WeatherLocation?> {
  WeatherLocationController({WeatherLocationStore? store})
      : _store = store ?? WeatherLocationStore(),
        super(null);

  final WeatherLocationStore _store;

  Future<void> load() async => state = await _store.load();

  Future<void> save(WeatherLocation location) async {
    state = location;
    await _store.save(location);
  }

  Future<void> clear() async {
    state = null;
    await _store.clear();
  }
}

final StateNotifierProvider<WeatherLocationController, WeatherLocation?>
    weatherLocationProvider =
    StateNotifierProvider<WeatherLocationController, WeatherLocation?>(
  (Ref ref) {
    final WeatherLocationController controller = WeatherLocationController(
      store: ref.read(weatherLocationStoreProvider),
    );
    scheduleMicrotask(controller.load);
    return controller;
  },
);

enum WeatherStatus { unset, loading, success, error }

/// Weather UI state. A failed refresh keeps the last successful observation and
/// marks it as cached, so the tile never flashes a fake value.
class WeatherState {
  const WeatherState({
    this.status = WeatherStatus.unset,
    this.snapshot,
    this.message,
    this.updatedAt,
  });

  final WeatherStatus status;
  final WeatherSnapshot? snapshot;
  final String? message;
  final DateTime? updatedAt;

  bool get isLoading => status == WeatherStatus.loading;
  bool get hasSnapshot => snapshot != null;
}

class WeatherController extends StateNotifier<WeatherState> {
  WeatherController(this._repository) : super(const WeatherState());

  static const Duration refreshInterval = Duration(minutes: 15);

  final WeatherRepository _repository;
  Timer? _timer;
  WeatherLocation? _location;
  bool _inFlight = false;
  bool _disposed = false;

  /// Called whenever the saved location changes (including the initial load).
  void observe(WeatherLocation? location) {
    if (_disposed) return;
    if (location == _location) return;
    _timer?.cancel();
    _timer = null;
    _location = location;
    if (location == null) {
      state = const WeatherState();
      return;
    }
    unawaited(_fetch());
  }

  Future<void> refresh() => _fetch(force: true);

  /// Used when the app returns to the foreground. Periodic refresh already
  /// covers a long-lived session; this only catches a stale observation.
  void refreshIfStale() {
    if (_disposed || _location == null) return;
    final DateTime? updated = state.updatedAt;
    if (updated == null ||
        DateTime.now().difference(updated) >= refreshInterval) {
      unawaited(_fetch());
    }
  }

  Future<void> _fetch({bool force = false}) async {
    final WeatherLocation? location = _location;
    if (_disposed || location == null || _inFlight) return;
    if (!force && state.status == WeatherStatus.loading) return;

    _inFlight = true;
    state = WeatherState(
      status: WeatherStatus.loading,
      snapshot: state.snapshot,
      message: 'Updating weather…',
      updatedAt: state.updatedAt,
    );

    try {
      final WeatherSnapshot snapshot = await _repository.fetchCurrent(location);
      if (_disposed || _location != location) return;
      state = WeatherState(
        status: WeatherStatus.success,
        snapshot: snapshot,
        updatedAt: DateTime.now(),
      );
      _scheduleRefresh();
    } on WeatherFetchException catch (error) {
      if (_disposed || _location != location) return;
      state = WeatherState(
        status: WeatherStatus.error,
        snapshot: state.snapshot,
        message: error.message,
        updatedAt: state.updatedAt,
      );
    } on Object catch (error) {
      if (_disposed || _location != location) return;
      state = WeatherState(
        status: WeatherStatus.error,
        snapshot: state.snapshot,
        message: 'Weather could not be loaded: $error',
        updatedAt: state.updatedAt,
      );
    } finally {
      _inFlight = false;
    }
  }

  void _scheduleRefresh() {
    _timer?.cancel();
    _timer = Timer(refreshInterval, refreshIfStale);
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

final StateNotifierProvider<WeatherController, WeatherState> weatherProvider =
    StateNotifierProvider<WeatherController, WeatherState>((Ref ref) {
  final WeatherController controller =
      WeatherController(ref.read(weatherRepositoryProvider));
  ref.listen<WeatherLocation?>(
    weatherLocationProvider,
    (WeatherLocation? previous, WeatherLocation? next) {
      controller.observe(next);
    },
  );
  scheduleMicrotask(
      () => controller.observe(ref.read(weatherLocationProvider)));
  return controller;
});
