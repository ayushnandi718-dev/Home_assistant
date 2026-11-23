import 'dart:io';

import 'package:aura_hub/app/shell/app_top_bar.dart';
import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/in_memory_profile_pin_file.dart';

/// Fast in-memory stand-in so widget tests do not wait on the real PBKDF2 KDF.
class _FastPinStore extends ProfilePinStore {
  _FastPinStore(Directory directory)
      : super(
          directory: directory,
          iterations: 1000,
          lockoutFile: InMemoryProfilePinFile(),
        );

  String? _pin;

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> setPin(String pin) async {
    final String? error = ProfilePinStore.validatePin(pin);
    if (error != null) throw ArgumentError(error);
    _pin = pin;
  }

  @override
  Future<bool> verify(String pin) async => _pin == pin;
}

void main() {
  late Directory directory;
  late _FastPinStore store;
  late ProviderContainer container;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('aura_navbar_switch_');
    store = _FastPinStore(directory);
    container = ProviderContainer(
      overrides: <Override>[
        profilePinStoreProvider.overrideWithValue(store),
        dashboardStatusProvider.overrideWith(
          (Ref ref) => const DashboardConnectionStatus(),
        ),
        telemetryApiStateProvider.overrideWithValue(const TelemetryApiState()),
        unreadNotificationCountProvider.overrideWithValue(0),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<void> pumpTopBar(WidgetTester tester) async {
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: AppTopBar(location: AppRoutes.memory)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Workspace'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseAyush(WidgetTester tester) async {
    await tester.tap(find.text('Private workspace · PIN required'));
    await tester.pumpAndSettle();
  }

  Future<void> chooseFamily(WidgetTester tester) async {
    await tester.tap(find.text('Shared household workspace'));
    await tester.pumpAndSettle();
  }

  Future<void> unlockWith(WidgetTester tester, String pin) async {
    await tester.enterText(find.byType(TextField).first, pin);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Unlock AYUSH'));
    await tester.pumpAndSettle();
  }

  testWidgets('dropdown lists both profiles and marks the active one',
      (WidgetTester tester) async {
    await pumpTopBar(tester);
    await openMenu(tester);

    expect(find.text('Active profile'), findsOneWidget);
    expect(find.text('Shared household workspace'), findsOneWidget);
    expect(find.text('Private workspace · PIN required'), findsOneWidget);
    expect(find.text('Manage profiles & security'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('AYUSH to FAMILY switches without authentication',
      (WidgetTester tester) async {
    await container.read(profileSessionProvider.notifier).setupPin('4821');
    expect(container.read(profileSessionProvider).profile, AuraProfile.ayush);

    await pumpTopBar(tester);
    expect(find.text('AYUSH'), findsOneWidget);
    expect(
      find.image(const AssetImage('assets/avatars/ayush.webp')),
      findsOneWidget,
    );

    await openMenu(tester);
    await chooseFamily(tester);

    expect(container.read(profileSessionProvider).profile, AuraProfile.family);
    expect(
        container.read(profileSessionProvider).privateSessionActive, isFalse);
    expect(find.text('FAMILY'), findsOneWidget);
    expect(find.text('AYUSH'), findsNothing);
    expect(
      find.image(const AssetImage('assets/avatars/ayush.webp')),
      findsNothing,
    );
    expect(
      find.image(const AssetImage('assets/avatars/family.webp')),
      findsOneWidget,
    );
  });

  testWidgets(
      'FAMILY to AYUSH with the correct PIN switches via the controller',
      (WidgetTester tester) async {
    await container.read(profileSessionProvider.notifier).setupPin('4821');
    container.read(profileSessionProvider.notifier).openFamily();
    await pumpTopBar(tester);

    await openMenu(tester);
    await chooseAyush(tester);

    expect(find.text('Enter your AYUSH PIN'), findsOneWidget);
    await unlockWith(tester, '4821');

    expect(
      container.read(profileSessionProvider).privateSessionActive,
      isTrue,
    );
    expect(container.read(profileSessionProvider).profile, AuraProfile.ayush);
    expect(find.text('AYUSH'), findsOneWidget);
  });

  testWidgets(
      'a rejected PIN keeps the current profile and reports remaining '
      'attempts', (WidgetTester tester) async {
    await container.read(profileSessionProvider.notifier).setupPin('4821');
    container.read(profileSessionProvider.notifier).openFamily();
    await pumpTopBar(tester);

    await openMenu(tester);
    await chooseAyush(tester);
    await unlockWith(tester, '0000');

    expect(container.read(profileSessionProvider).profile, AuraProfile.family);
    expect(find.text('Incorrect PIN. 4 attempt(s) remaining.'), findsOneWidget);
    expect(find.text('Enter your AYUSH PIN'), findsOneWidget);
  });

  testWidgets('cancelling authentication stays in FAMILY',
      (WidgetTester tester) async {
    await container.read(profileSessionProvider.notifier).setupPin('4821');
    container.read(profileSessionProvider.notifier).openFamily();
    await pumpTopBar(tester);

    await openMenu(tester);
    await chooseAyush(tester);
    expect(find.text('Enter your AYUSH PIN'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(container.read(profileSessionProvider).profile, AuraProfile.family);
    expect(find.text('Enter your AYUSH PIN'), findsNothing);
  });

  testWidgets('repeated switches keep the navbar in sync',
      (WidgetTester tester) async {
    await container.read(profileSessionProvider.notifier).setupPin('4821');
    container.read(profileSessionProvider.notifier).openFamily();
    await pumpTopBar(tester);

    for (int round = 0; round < 3; round++) {
      await openMenu(tester);
      await chooseAyush(tester);
      await unlockWith(tester, '4821');
      expect(container.read(profileSessionProvider).profile, AuraProfile.ayush);
      expect(find.text('AYUSH'), findsOneWidget);

      await openMenu(tester);
      await chooseFamily(tester);
      expect(
          container.read(profileSessionProvider).profile, AuraProfile.family);
      expect(find.text('FAMILY'), findsOneWidget);
    }
  });
}
