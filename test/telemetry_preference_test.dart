import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_controller.dart';
import 'package:aura_hub/core/settings/app_settings_store.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_service.dart';
import 'package:aura_hub/core/telemetry/telemetry_log_store.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemorySettingsStore extends AppSettingsStore {
  _MemorySettingsStore(this.settings) : super(directory: Directory.systemTemp);

  AppSettings settings;

  @override
  Future<AppSettings> load() async => settings;

  @override
  Future<void> save(AppSettings value) async => settings = value;
}

class _SilentLogStore extends TelemetryApiLogStore {
  _SilentLogStore() : super(directory: Directory.systemTemp);

  @override
  Future<void> append(String event, {String? detail}) async {}

  @override
  void appendSync(String event, {String? detail}) {}
}

void main() {
  test('telemetry lifecycle follows the persisted enable preference', () async {
    final _MemorySettingsStore store = _MemorySettingsStore(
      const AppSettings(telemetryEnabled: false),
    );
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        appSettingsProvider.overrideWith(
          (Ref ref) => AppSettingsController(store: store),
        ),
        telemetryApiLogStoreProvider.overrideWithValue(_SilentLogStore()),
      ],
    );
    addTearDown(container.dispose);
    await container.read(appSettingsProvider.notifier).load();

    final TelemetryApiService disabledService =
        container.read(telemetryApiServiceProvider.notifier);
    expect(disabledService.enabled, isFalse);
    expect(disabledService.state.issue, TelemetryApiIssue.disabled);
    expect(container.read(telemetryApiStateProvider).issue,
        TelemetryApiIssue.disabled);

    await container.read(appSettingsProvider.notifier).update(
          store.settings.copyWith(telemetryEnabled: true),
        );

    final TelemetryApiService enabledService =
        container.read(telemetryApiServiceProvider.notifier);
    expect(enabledService.enabled, isTrue);
    expect(enabledService, isNot(same(disabledService)),
        reason: 'changing the preference rebuilds the service so the old '
            'AURA-owned process is shut down through onDispose');
    expect(enabledService.state.issue, isNot(TelemetryApiIssue.disabled));
  });
}
