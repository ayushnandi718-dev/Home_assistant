import 'dart:async';

import 'package:aura_hub/core/lifecycle/background_service.dart';
import 'package:aura_hub/core/network/aura_api_client.dart';

/// Periodically checks AURA service health in the background.
///
/// The probe is injected: in production it calls the real local API client;
/// in tests it is a plain function. It never starts, stops or spawns a process.
class ServiceHealthMonitor implements AuraBackgroundService {
  ServiceHealthMonitor({
    required this.probe,
    required this.onResult,
    this.interval = const Duration(seconds: 30),
  });

  final Future<ApiHealth> Function() probe;
  final void Function(ApiHealth health) onResult;
  final Duration interval;

  Timer? _timer;
  bool _started = false;
  bool _paused = false;
  bool _inFlight = false;

  @override
  String get name => 'aura-service-health';

  @override
  void start() {
    if (_started) return;
    _started = true;
    _paused = false;
    unawaited(checkNow());
    _timer = Timer.periodic(interval, (Timer _) => unawaited(checkNow()));
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _paused = false;
  }

  @override
  void pause() {
    _paused = true;
  }

  @override
  void resume() {
    if (!_started || !_paused) return;
    _paused = false;
    unawaited(checkNow());
  }

  /// Runs one check. Concurrent ticks are skipped so a slow API cannot cause
  /// overlapping requests or out-of-order health results.
  Future<ApiHealth?> checkNow() async {
    if (!_started || _paused || _inFlight) return null;
    _inFlight = true;
    try {
      final ApiHealth health = await probe();
      if (_started && !_paused) onResult(health);
      return health;
    } finally {
      _inFlight = false;
    }
  }
}
