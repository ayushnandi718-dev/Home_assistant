import 'dart:async';

import 'package:aura_hub/core/lifecycle/background_service.dart';
import 'package:aura_hub/core/lifecycle/service_health_monitor.dart';
import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService implements AuraBackgroundService {
  _FakeService(this.name);

  @override
  final String name;

  int starts = 0;
  int stops = 0;
  int pauses = 0;
  int resumes = 0;

  @override
  void start() => starts++;

  @override
  void stop() => stops++;

  @override
  void pause() => pauses++;

  @override
  void resume() => resumes++;
}

ApiHealth _healthy() => ApiHealth(
      checkedAt: DateTime.now(),
      responseTime: const Duration(milliseconds: 5),
      samplerReady: true,
      samplerHealthy: true,
    );

void main() {
  group('ServiceLifecycleManager', () {
    late ServiceLifecycleManager manager;
    late _FakeService first;

    setUp(() {
      manager = ServiceLifecycleManager();
      first = _FakeService('first');
    });

    test('register ignores duplicate names', () {
      manager.register(first);
      manager.register(_FakeService('first'));
      manager.register(_FakeService('second'));

      expect(manager.serviceNames, <String>['first', 'second']);
    });

    test('startAll and stopAll are idempotent', () {
      manager.register(first);
      expect(manager.running, isFalse);

      manager.startAll();
      manager.startAll();
      expect(manager.running, isTrue);
      expect(first.starts, 1);

      manager.stopAll();
      manager.stopAll();
      expect(manager.running, isFalse);
      expect(first.stops, 1);
    });

    test('pause and resume are idempotent and only apply while running', () {
      manager.register(first);
      manager.pauseAll();
      expect(first.pauses, 0);

      manager.startAll();
      manager.pauseAll();
      manager.pauseAll();
      expect(manager.paused, isTrue);
      expect(first.pauses, 1);

      manager.resumeAll();
      manager.resumeAll();
      expect(manager.paused, isFalse);
      expect(first.resumes, 1);
    });
  });

  group('ServiceHealthMonitor', () {
    late List<Completer<ApiHealth>> probes;
    late List<ApiHealth> results;
    late ServiceHealthMonitor monitor;

    setUp(() {
      probes = <Completer<ApiHealth>>[];
      results = <ApiHealth>[];
      monitor = ServiceHealthMonitor(
        interval: const Duration(seconds: 30),
        probe: () {
          final Completer<ApiHealth> completer = Completer<ApiHealth>();
          probes.add(completer);
          return completer.future;
        },
        onResult: results.add,
      );
    });

    tearDown(() => monitor.stop());

    test('does not probe before it is started', () async {
      expect(await monitor.checkNow(), isNull);
      expect(probes, isEmpty);
    });

    test('starting runs one immediate check and delivers the result', () async {
      monitor.start();
      expect(probes.length, 1);

      probes.first.complete(_healthy());
      await Future<void>.delayed(Duration.zero);

      expect(results.length, 1);
      expect(results.single.reachable, isTrue);
    });

    test('skips a concurrent check while one is in flight', () async {
      monitor.start();
      expect(await monitor.checkNow(), isNull);
      expect(probes.length, 1);
    });

    test('pause blocks checks and resume triggers a new one', () async {
      monitor.start();
      monitor.pause();

      expect(await monitor.checkNow(), isNull);
      expect(probes.length, 1);

      probes.first.complete(_healthy());
      await Future<void>.delayed(Duration.zero);

      monitor.resume();
      expect(probes.length, 2);
    });

    test('stop cancels further checks', () async {
      monitor.start();
      probes.first.complete(_healthy());
      await Future<void>.delayed(Duration.zero);

      monitor.stop();
      expect(await monitor.checkNow(), isNull);
      expect(probes.length, 1);
    });
  });
}
