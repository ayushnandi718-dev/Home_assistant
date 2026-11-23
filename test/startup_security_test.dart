import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_controller.dart';
import 'package:aura_hub/core/settings/app_settings_store.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/startup/data/startup_service.dart';
import 'package:aura_hub/features/startup/data/windows_startup_service.dart';
import 'package:aura_hub/features/startup/presentation/startup_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _RecordedApply {
  const _RecordedApply(this.enabled, this.startMinimized);

  final bool enabled;
  final bool startMinimized;
}

class _FakeStartupService implements StartupService {
  @override
  bool supported = true;
  final List<_RecordedApply> applies = <_RecordedApply>[];
  bool fail = false;
  int minimizeCalls = 0;

  @override
  Future<StartupApplyResult> apply({
    required bool enabled,
    required bool startMinimized,
  }) async {
    applies.add(_RecordedApply(enabled, startMinimized));
    if (fail) {
      return const StartupApplyResult(ok: false, error: 'simulated failure');
    }
    return const StartupApplyResult(ok: true);
  }

  @override
  Future<StartupRegistration> read() async => StartupRegistration(
        supported: supported,
        registered: applies.isNotEmpty,
      );

  @override
  void minimizeIfRequested(bool startMinimized) {
    if (startMinimized) minimizeCalls++;
  }
}

class _MemorySettingsStore extends AppSettingsStore {
  _MemorySettingsStore(this.settings) : super(directory: Directory.systemTemp);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings value) async => settings = value;
}

class _FastPinStore extends ProfilePinStore {
  _FastPinStore() : super(directory: Directory.systemTemp, iterations: 1000);

  String? _pin;

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> setPin(String pin, {bool Function()? isCommitAllowed}) async =>
      _pin = pin;

  @override
  Future<bool> verify(String pin, {bool Function()? isCommitAllowed}) async =>
      _pin == pin;
}

ProviderContainer _container(_MemorySettingsStore settingsStore) {
  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appSettingsProvider.overrideWith(
        (Ref ref) => AppSettingsController(store: settingsStore),
      ),
      profilePinStoreProvider.overrideWithValue(_FastPinStore()),
      startupServiceProvider
          .overrideWithValue(const UnsupportedStartupService()),
    ],
  );
  return container;
}

void main() {
  group('Windows startup preference', () {
    test('controller forwards both flags and keeps the last outcome', () async {
      final _FakeStartupService service = _FakeStartupService();
      final StartupController controller = StartupController(service: service);
      addTearDown(controller.dispose);

      const AppSettings enabled = AppSettings(
        launchAtStartup: true,
        startMinimized: true,
      );
      await controller.apply(enabled);
      expect(service.applies, hasLength(1));
      expect(service.applies.single.enabled, isTrue);
      expect(service.applies.single.startMinimized, isTrue);
      expect(controller.state.applying, isFalse);
      expect(controller.state.result?.ok, isTrue);

      const AppSettings disabled = AppSettings(launchAtStartup: false);
      await controller.apply(disabled);
      expect(service.applies, hasLength(2));
      expect(service.applies.last.enabled, isFalse);
      expect(service.applies.last.startMinimized, isFalse);
    });

    test('unsupported platforms and failures are reported honestly', () async {
      final StartupController unsupported =
          StartupController(service: const UnsupportedStartupService());
      addTearDown(unsupported.dispose);
      await unsupported.apply(const AppSettings(launchAtStartup: true));
      expect(unsupported.state.result?.ok, isFalse);
      expect(unsupported.state.result?.error, contains('unavailable'));

      final _FakeStartupService failing = _FakeStartupService()..fail = true;
      final StartupController controller = StartupController(service: failing);
      addTearDown(controller.dispose);
      await controller.apply(const AppSettings(launchAtStartup: true));
      expect(controller.state.result?.ok, isFalse);
      expect(controller.state.result?.error, 'simulated failure');
    });

    test('the startup command contains only the executable and a benign flag',
        () {
      const String pathWithSpaces = r'C:\Program Files\AURA Hub\aura_hub.exe';
      expect(
        WindowsStartupService.buildCommand(
          pathWithSpaces,
          startMinimized: false,
        ),
        '"$pathWithSpaces"',
      );
      expect(
        WindowsStartupService.buildCommand(
          pathWithSpaces,
          startMinimized: true,
        ),
        '"$pathWithSpaces" --start-minimized',
      );
      expect(
        WindowsStartupService.buildCommand(
          r'C:\aura_hub.exe',
          startMinimized: false,
        ),
        r'C:\aura_hub.exe',
      );

      final String command = WindowsStartupService.buildCommand(
        pathWithSpaces,
        startMinimized: true,
      );
      for (final String secretMarker in <String>[
        'PIN',
        'pin=',
        'password',
        'secret',
        'token',
        'ayush_security',
        '--user',
      ]) {
        expect(
          command.toLowerCase().contains(secretMarker.toLowerCase()),
          isFalse,
          reason: 'startup must never store authentication material',
        );
      }
      expect(WindowsStartupService.valueName, 'AURA Hub');
    });
  });

  group('remembered profile and restart behaviour', () {
    test('only a remembered AYUSH scope prompts for the PIN', () async {
      final _MemorySettingsStore settingsStore = _MemorySettingsStore(
        const AppSettings(
          rememberLastProfile: true,
          lastActiveProfile: 'ayush',
        ),
      );
      final ProviderContainer container = _container(settingsStore);
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.notifier).load();

      expect(container.read(shouldPromptAyushUnlockProvider), isTrue);
      // The remembered scope is a prompt only: the session starts in FAMILY.
      expect(
          container.read(profileSessionProvider).privateSessionActive, isFalse);
      expect(
          container.read(profileSessionProvider).profile, AuraProfile.family);

      await container.read(appSettingsProvider.notifier).update(
            const AppSettings(
              rememberLastProfile: true,
              lastActiveProfile: 'family',
            ),
          );
      expect(container.read(shouldPromptAyushUnlockProvider), isFalse);

      await container.read(appSettingsProvider.notifier).update(
            const AppSettings(
              rememberLastProfile: false,
              lastActiveProfile: 'ayush',
            ),
          );
      expect(container.read(shouldPromptAyushUnlockProvider), isFalse);
    });

    test('the tracker saves only scopes and never unlocks the session',
        () async {
      final _MemorySettingsStore settingsStore = _MemorySettingsStore(
        const AppSettings(rememberLastProfile: true),
      );
      final ProviderContainer container = _container(settingsStore);
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.notifier).load();
      container.read(rememberedProfileTrackerProvider);

      await container.read(profileSessionProvider.notifier).setupPin('1234');
      await Future<void>.delayed(Duration.zero);
      expect(settingsStore.settings.lastActiveProfile, 'ayush');
      expect(settingsStore.settings.rememberLastProfile, isTrue);
      expect(settingsStore.settings.lastActiveProfile, isNot(contains('1234')));

      container.read(profileSessionProvider.notifier).openFamily();
      await Future<void>.delayed(Duration.zero);
      expect(settingsStore.settings.lastActiveProfile, 'family');
    });

    test('turning the preference off forgets the remembered scope', () async {
      final _MemorySettingsStore settingsStore = _MemorySettingsStore(
        const AppSettings(rememberLastProfile: true),
      );
      final ProviderContainer container = _container(settingsStore);
      addTearDown(container.dispose);
      await container.read(appSettingsProvider.notifier).load();
      container.read(rememberedProfileTrackerProvider);

      await container.read(profileSessionProvider.notifier).setupPin('1234');
      await Future<void>.delayed(Duration.zero);
      expect(settingsStore.settings.lastActiveProfile, 'ayush');

      await container.read(appSettingsProvider.notifier).update(
            container.read(appSettingsProvider).copyWith(
                  rememberLastProfile: false,
                  clearLastActiveProfile: true,
                ),
          );
      expect(settingsStore.settings.lastActiveProfile, isNull);
      expect(container.read(shouldPromptAyushUnlockProvider), isFalse);
    });

    test('a restart with remembered AYUSH still starts locked in FAMILY',
        () async {
      final _MemorySettingsStore persisted = _MemorySettingsStore(
        const AppSettings(
          rememberLastProfile: true,
          lastActiveProfile: 'ayush',
        ),
      );
      final ProviderContainer firstRun = _container(persisted);
      await firstRun.read(appSettingsProvider.notifier).load();
      firstRun.read(rememberedProfileTrackerProvider);
      await firstRun.read(profileSessionProvider.notifier).setupPin('1234');
      await Future<void>.delayed(Duration.zero);
      expect(persisted.settings.lastActiveProfile, 'ayush');
      firstRun.dispose();

      // Simulate a fresh process reading the same persisted settings.
      final ProviderContainer restarted = _container(persisted);
      addTearDown(restarted.dispose);
      await restarted.read(appSettingsProvider.notifier).load();
      restarted.read(rememberedProfileTrackerProvider);

      expect(restarted.read(shouldPromptAyushUnlockProvider), isTrue);
      expect(
          restarted.read(profileSessionProvider).profile, AuraProfile.family);
      expect(
          restarted.read(profileSessionProvider).privateSessionActive, isFalse);
    });
  });
}
