import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_controller.dart';
import 'package:aura_hub/core/settings/app_settings_store.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/profiles/presentation/profiles_page.dart';
import 'package:aura_hub/features/security/data/ayush_security_settings_store.dart';
import 'package:aura_hub/features/security/domain/ayush_security_settings.dart';
import 'package:aura_hub/features/security/presentation/security_providers.dart';
import 'package:aura_hub/features/settings/presentation/settings_page.dart';
import 'package:aura_hub/features/startup/data/startup_service.dart';
import 'package:aura_hub/features/startup/presentation/startup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/in_memory_profile_pin_file.dart';

class _FastPinStore extends ProfilePinStore {
  _FastPinStore()
      : super(
          directory: Directory.systemTemp,
          iterations: 1000,
          lockoutFile: InMemoryProfilePinFile(),
        );

  String? _pin;

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> setPin(String pin) async => _pin = pin;

  @override
  Future<bool> verify(String pin) async => _pin == pin;
}

class _MemorySecurityStorage implements AyushSecuritySettingsStorage {
  @override
  Future<AyushSecuritySettings> load() async => AyushSecuritySettings.defaults;

  @override
  Future<void> save(AyushSecuritySettings settings) async {}
}

class _MemorySettingsStore extends AppSettingsStore {
  _MemorySettingsStore(this.settings) : super(directory: Directory.systemTemp);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings value) async => settings = value;
}

void main() {
  group('Profiles & Security page', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(
        overrides: <Override>[
          profilePinStoreProvider.overrideWithValue(_FastPinStore()),
          ayushSecuritySettingsStoreProvider
              .overrideWithValue(_MemorySecurityStorage()),
        ],
      );
    });

    tearDown(() => container.dispose());

    Future<void> pumpPage(WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: ProfilesPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('private security controls appear only for unlocked AYUSH',
        (WidgetTester tester) async {
      await pumpPage(tester);
      expect(find.text('Change AYUSH PIN'), findsNothing);
      expect(find.text('Automatic AYUSH lock'), findsNothing);

      await container.read(profileSessionProvider.notifier).setupPin('4821');
      await tester.pumpAndSettle();

      expect(find.text('Change AYUSH PIN'), findsOneWidget);
      expect(find.text('Automatic AYUSH lock'), findsOneWidget);
      expect(
        find.textContaining(
          'Defaults: 5 minutes inactivity, 30 seconds background.',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('Windows Hello is not implemented'),
        findsOneWidget,
        reason: 'no fake biometric toggle may be shown',
      );

      container.read(profileSessionProvider.notifier).lock();
      await tester.pumpAndSettle();
      expect(find.text('Change AYUSH PIN'), findsNothing);
    });
  });

  group('Settings page', () {
    late ProviderContainer container;

    setUp(() async {
      final _MemorySettingsStore settingsStore = _MemorySettingsStore(
        const AppSettings(
          themeMode: AuraThemeMode.light,
          telemetryEnabled: false,
        ),
      );
      container = ProviderContainer(
        overrides: <Override>[
          appSettingsProvider.overrideWith(
            (Ref ref) => AppSettingsController(store: settingsStore),
          ),
          telemetryApiStateProvider
              .overrideWithValue(const TelemetryApiState()),
          startupControllerProvider.overrideWith(
            (Ref ref) => StartupController(
              service: const UnsupportedStartupService(),
            ),
          ),
        ],
      );
      await container.read(appSettingsProvider.notifier).load();
    });

    tearDown(() => container.dispose());

    testWidgets('shows all Phase 4 sections with honest status',
        (WidgetTester tester) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: SettingsPage())),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Appearance'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Telemetry'), findsOneWidget);
      expect(find.text('Startup & behaviour'), findsOneWidget);
      expect(find.text('About'), findsOneWidget);
      expect(find.textContaining('English-only'), findsOneWidget);
      expect(find.text('Launch AURA when Windows starts'), findsOneWidget);
      expect(find.text('Remember last active profile'), findsOneWidget);
      expect(find.text('Service: Disabled'), findsOneWidget);

      final DropdownButton<AuraThemeMode> themeDropdown =
          tester.widget<DropdownButton<AuraThemeMode>>(
        find.byType(DropdownButton<AuraThemeMode>).first,
      );
      expect(themeDropdown.value, AuraThemeMode.light);

      final DropdownButton<AuraLanguage> languageDropdown =
          tester.widget<DropdownButton<AuraLanguage>>(
        find.byType(DropdownButton<AuraLanguage>),
      );
      expect(languageDropdown.value, AuraLanguage.auto);
    });
  });
}
