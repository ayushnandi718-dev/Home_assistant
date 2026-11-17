import 'dart:io';

import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/notifications/data/notification_store.dart';
import 'package:aura_hub/features/notifications/domain/aura_notification.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/features/system/presentation/service_health_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

ApiHealth _healthy() => ApiHealth(
      checkedAt: DateTime.now(),
      responseTime: const Duration(milliseconds: 5),
      samplerReady: true,
      samplerHealthy: true,
    );

ApiHealth _offline() => ApiHealth.failure(
      checkedAt: DateTime.now(),
      responseTime: Duration.zero,
      error: 'Connection refused',
    );

ApiHealth _samplerDegraded() => ApiHealth(
      checkedAt: DateTime.now(),
      responseTime: const Duration(milliseconds: 6),
      samplerReady: true,
      samplerHealthy: false,
      samplerLastError: 'Sampler loop failed',
    );

void main() {
  group('ServiceHealthController transition notifications', () {
    late Directory directory;
    late NotificationCenter center;
    late ProviderContainer container;
    late ServiceHealthController controller;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_health_test_');
      center = NotificationCenter(NotificationStore(directory: directory));
      container = ProviderContainer(
        overrides: <Override>[
          activeNotificationCenterProvider.overrideWithValue(center),
        ],
      );
      controller = container.read(serviceHealthProvider.notifier);
    });

    tearDown(() {
      container.dispose();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('a first healthy check does not create a notification', () {
      controller.observe(_healthy());
      expect(center.state, isEmpty);
      expect(container.read(serviceHealthProvider)?.reachable, isTrue);
    });

    test('a first offline check raises one API notification', () {
      controller.observe(_offline());
      expect(center.state.length, 1);
      expect(center.state.single.source, NotificationSource.api);
      expect(center.state.single.severity, NotificationSeverity.error);
    });

    test('offline then online replaces one stable notification', () {
      controller.observe(_healthy());
      controller.observe(_offline());
      expect(center.state.length, 1);
      expect(center.state.single.title, contains('offline'));

      controller.observe(_healthy());
      expect(center.state.length, 1);
      expect(center.state.single.title, contains('online'));
      expect(center.state.single.severity, NotificationSeverity.success);
    });

    test('sampler degradation raises a separate notification', () {
      controller.observe(_healthy());
      controller.observe(_samplerDegraded());

      expect(center.state.length, 1);
      expect(center.state.single.source, NotificationSource.sampler);
      expect(center.state.single.title, contains('degraded'));
    });

    test('repeated healthy checks do not spam the centre', () {
      controller.observe(_healthy());
      controller.observe(_healthy());
      controller.observe(_healthy());
      expect(center.state, isEmpty);
    });
  });
}
