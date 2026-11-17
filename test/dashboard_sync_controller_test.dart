import 'dart:async';

import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:fake_async/fake_async.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_sync_controller.dart';
import 'package:flutter_test/flutter_test.dart';

DashboardSnapshot _snapshot({double cpu = 10}) => DashboardSnapshot(
      devices: const [],
      activity: const [],
      coreLink: CoreLinkState.notLinked,
      localApiOnline: true,
      network: NetworkReadiness.configured,
      security: SecurityReadiness.ready,
      generatedAt: DateTime(2026, 1, 1, 12),
      isDemo: false,
      apiUrl: '127.0.0.1:8765',
      system: SystemMetrics(
        hostName: 'TEST-PC',
        osName: 'Windows',
        bootTime: DateTime(2026, 1, 1),
        uptimeSeconds: 3600,
        cpuPercent: cpu,
        cpuCores: 4,
        cpuFrequencyMHz: 2400,
        perCoreCpu: const <double>[10, 10, 10, 10],
        memoryTotalBytes: 8 * 1024 * 1024 * 1024,
        memoryUsedBytes: 4 * 1024 * 1024 * 1024,
        memoryAvailableBytes: 4 * 1024 * 1024 * 1024,
        memoryPercent: 50,
        diskPath: 'C:\\',
        diskTotalBytes: 100 * 1024 * 1024 * 1024,
        diskUsedBytes: 40 * 1024 * 1024 * 1024,
        diskFreeBytes: 60 * 1024 * 1024 * 1024,
        diskPercent: 40,
        bytesSent: 1000,
        bytesReceived: 2000,
        sentPerSecond: 10,
        receivedPerSecond: 20,
        activeInterfaceCount: 1,
        processCount: 100,
        topProcesses: const <TopProcess>[],
        batteryPercent: 80,
        batteryPlugged: true,
        batterySecondsLeft: null,
        firewallEnabled: true,
        firewallState: FirewallReadiness.enabled,
      ),
    );

void main() {
  test('fetches immediately then every 3 seconds', () {
    fakeAsync((FakeAsync async) {
      int calls = 0;
      final DashboardSyncController controller = DashboardSyncController(
        fetch: () async {
          calls++;
          return _snapshot();
        },
        interval: const Duration(seconds: 3),
      );
      addTearDown(controller.dispose);

      controller.stream.listen((DashboardSnapshot _) {});
      controller.start();
      async.flushMicrotasks();
      expect(calls, 1, reason: 'first fetch happens on start');

      async.elapse(const Duration(seconds: 9));
      expect(calls, 4, reason: 'polls at 3s, 6s and 9s');
    });
  });

  test('does not overlap requests while a fetch is in flight', () {
    fakeAsync((FakeAsync async) {
      int calls = 0;
      Completer<DashboardSnapshot>? pending;
      final DashboardSyncController controller = DashboardSyncController(
        fetch: () {
          calls++;
          pending = Completer<DashboardSnapshot>();
          return pending!.future;
        },
        interval: const Duration(seconds: 3),
      );
      addTearDown(controller.dispose);

      controller.stream.listen((DashboardSnapshot _) {});
      controller.start();
      async.flushMicrotasks();
      expect(calls, 1);

      async.elapse(const Duration(seconds: 9));
      expect(calls, 1, reason: 'no second request until the first completes');

      pending!.complete(_snapshot());
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 3));
      expect(calls, 2);
    });
  });

  test('keeps last good metrics and marks them stale when a poll fails', () {
    fakeAsync((FakeAsync async) {
      bool fail = false;
      final List<DashboardSnapshot> received = <DashboardSnapshot>[];
      final DashboardSyncController controller = DashboardSyncController(
        fetch: () async {
          if (fail) throw StateError('API unavailable');
          return _snapshot(cpu: 42);
        },
        interval: const Duration(seconds: 3),
      );
      addTearDown(controller.dispose);

      controller.stream.listen(received.add);
      controller.start();
      async.flushMicrotasks();

      fail = true;
      async.elapse(const Duration(seconds: 3));

      expect(received.length, 2);
      final DashboardSnapshot stale = received.last;
      expect(stale.stale, isTrue);
      expect(stale.localApiOnline, isFalse);
      expect(stale.system.cpuPercent, 42, reason: 'last good readings kept');
    });
  });

  test('recovers after a timeout and restores the live state', () {
    fakeAsync((FakeAsync async) {
      bool timedOut = false;
      final List<DashboardSnapshot> received = <DashboardSnapshot>[];
      final statuses = <DashboardConnectionStatus>[];
      final DashboardSyncController controller = DashboardSyncController(
        fetch: () async {
          if (timedOut) {
            throw TimeoutException('no response', Duration(seconds: 5));
          }
          return _snapshot(cpu: 47);
        },
        interval: const Duration(seconds: 3),
        onStatus: statuses.add,
      );
      addTearDown(controller.dispose);

      controller.stream.listen(received.add);
      controller.start();
      async.flushMicrotasks();

      timedOut = true;
      async.elapse(const Duration(seconds: 3));
      expect(received.last.stale, isTrue);
      expect(statuses.last.stale, isTrue);
      expect(statuses.last.localApiOnline, isFalse);

      timedOut = false;
      async.elapse(const Duration(seconds: 3));
      expect(received.last.stale, isFalse);
      expect(received.last.localApiOnline, isTrue);
      expect(statuses.last.localApiOnline, isTrue);
      expect(statuses.last.error, isNull);
    });
  });

  test('publishes an idle status when disposed', () {
    fakeAsync((FakeAsync async) {
      final statuses = <DashboardConnectionStatus>[];
      final DashboardSyncController controller = DashboardSyncController(
        fetch: () async => _snapshot(),
        interval: const Duration(seconds: 3),
        onStatus: statuses.add,
      );
      controller.stream.listen((DashboardSnapshot _) {});
      controller.start();
      async.flushMicrotasks();
      expect(statuses.last.active, isTrue);

      controller.dispose();
      expect(statuses.last.active, isFalse);
    });
  });

  test('start is idempotent and never creates duplicate timers', () {
    fakeAsync((FakeAsync async) {
      int calls = 0;
      final DashboardSyncController controller = DashboardSyncController(
        fetch: () async {
          calls++;
          return _snapshot();
        },
        interval: const Duration(seconds: 3),
      );
      addTearDown(controller.dispose);

      controller.stream.listen((DashboardSnapshot _) {});
      controller.start();
      controller.start();
      controller.start();
      expect(controller.isPolling, isTrue);
      async.flushMicrotasks();
      expect(calls, 1, reason: 'only one immediate fetch');

      async.elapse(const Duration(seconds: 3));
      expect(calls, 2, reason: 'only one periodic timer');
    });
  });

  test('cancels its timer on dispose', () {
    fakeAsync((FakeAsync async) {
      int calls = 0;
      final DashboardSyncController controller = DashboardSyncController(
        fetch: () async {
          calls++;
          return _snapshot();
        },
        interval: const Duration(seconds: 3),
      );
      controller.stream.listen((DashboardSnapshot _) {});
      controller.start();
      async.flushMicrotasks();
      controller.dispose();
      expect(controller.isPolling, isFalse);

      async.elapse(const Duration(seconds: 30));
      expect(calls, 1, reason: 'no polling after dispose');
    });
  });
}
