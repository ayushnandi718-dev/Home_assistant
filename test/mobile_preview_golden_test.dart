import 'dart:io';
import 'dart:typed_data';

import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/core/services/clock_service.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_controller.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/features/dashboard/domain/activity_event.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show FontLoader;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _goldenFontFamily = 'Inter';

Future<void> _loadGoldenFonts() async {
  final FontLoader loader = FontLoader(_goldenFontFamily);
  for (final String fileName in <String>[
    'Inter-Regular.ttf',
    'Inter-Medium.ttf',
    'Inter-SemiBold.ttf',
  ]) {
    final Uint8List bytes = File('test/fonts/$fileName').readAsBytesSync();
    loader.addFont(
      Future<ByteData>.value(
        ByteData.view(bytes.buffer, bytes.offsetInBytes, bytes.lengthInBytes),
      ),
    );
  }
  await loader.load();
}

class _PreviewDashboardRepository implements DashboardRepository {
  @override
  Future<DashboardSnapshot> loadDashboard() async {
    final DateTime now = DateTime.now();
    return DashboardSnapshot(
      devices: const <AuraDevice>[],
      activity: <ActivityEvent>[
        ActivityEvent(
          id: 'preview-event',
          title: 'AURA Core online',
          detail: 'Preview data rendered at a mobile viewport.',
          category: ActivityCategory.system,
          severity: ActivitySeverity.info,
          timestamp: now,
          isDemo: false,
        ),
      ],
      coreLink: CoreLinkState.notLinked,
      localApiOnline: true,
      network: NetworkReadiness.configured,
      security: SecurityReadiness.ready,
      generatedAt: now,
      isDemo: false,
      apiUrl: '127.0.0.1:8765',
      system: SystemMetrics(
        hostName: 'AURA-PREVIEW',
        osName: 'Flutter widget preview',
        bootTime: now,
        uptimeSeconds: 3600,
        cpuPercent: 12,
        cpuCores: 4,
        cpuFrequencyMHz: 2400,
        perCoreCpu: const <double>[12, 12, 12, 12],
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
  }
}

void main() {
  testWidgets('mobile viewport preview renders the AURA Home shell',
      (WidgetTester tester) async {
    await _loadGoldenFonts();

    tester.view.physicalSize = const Size(460, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          appSettingsProvider.overrideWith((Ref ref) {
            final AppSettingsController controller = AppSettingsController();
            controller.state = AppSettings.defaults.copyWith(
              visualStyle: AuraVisualStyle.violet,
            );
            return controller;
          }),
          dashboardRepositoryProvider
              .overrideWithValue(_PreviewDashboardRepository()),
          displayClockProvider.overrideWithValue(
            FixedAuraClock(DateTime.utc(2026, 11, 21, 9, 30)),
          ),
        ],
        child: const DefaultTextStyle(
          style: TextStyle(fontFamily: _goldenFontFamily),
          child: AuraApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await expectLater(
      find.byType(AuraApp),
      matchesGoldenFile('goldens/mobile_home_preview.png'),
    );
  }, tags: 'golden');
}
