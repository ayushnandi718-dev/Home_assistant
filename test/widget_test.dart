import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/features/dashboard/data/mock_dashboard_repository.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/devices/data/mock_device_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dashboard renders demo data and navigation works',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dashboardRepositoryProvider.overrideWithValue(
            MockDashboardRepository(
              deviceRepository:
                  const MockDeviceRepository(latency: Duration.zero),
              latency: Duration.zero,
            ),
          ),
        ],
        child: const AuraApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Demonstration data'), findsOneWidget);
    expect(find.text('AURA Desk'), findsOneWidget);
    expect(find.text('Recent system events'), findsOneWidget);

    await tester.tap(find.text('Devices').first);
    await tester.pumpAndSettle();

    expect(find.text('Planned capabilities'), findsOneWidget);
    expect(find.textContaining('No fake pairing'), findsOneWidget);
  });
}
