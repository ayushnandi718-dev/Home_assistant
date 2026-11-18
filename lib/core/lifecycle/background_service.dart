/// A service that runs without a visible screen and has an explicit lifecycle.
///
/// Implementations must never spawn operating-system processes. They manage
/// in-process timers/streams only; the separate telemetry service owns the
/// hidden Python API process lifecycle.
abstract class AuraBackgroundService {
  const AuraBackgroundService();

  String get name;

  void start();

  void stop();

  void pause();

  void resume();
}

/// Tracks registered background services and reacts to application lifecycle.
class ServiceLifecycleManager {
  final List<AuraBackgroundService> _services = <AuraBackgroundService>[];
  bool _running = false;
  bool _paused = false;

  List<String> get serviceNames =>
      _services.map((AuraBackgroundService service) => service.name).toList();

  bool get running => _running;

  bool get paused => _paused;

  void register(AuraBackgroundService service) {
    if (_services.any((AuraBackgroundService s) => s.name == service.name)) {
      return;
    }
    _services.add(service);
    if (_running && !_paused) service.start();
  }

  void startAll() {
    if (_running) return;
    _running = true;
    _paused = false;
    for (final AuraBackgroundService service in _services) {
      service.start();
    }
  }

  void pauseAll() {
    if (!_running || _paused) return;
    _paused = true;
    for (final AuraBackgroundService service in _services) {
      service.pause();
    }
  }

  void resumeAll() {
    if (!_running || !_paused) return;
    _paused = false;
    for (final AuraBackgroundService service in _services) {
      service.resume();
    }
  }

  void stopAll() {
    if (!_running) return;
    _running = false;
    _paused = false;
    for (final AuraBackgroundService service in _services) {
      service.stop();
    }
  }
}
