import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_controller.dart';
import 'package:aura_hub/core/settings/app_settings_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('aura_settings_test_');
  });

  tearDown(() async {
    if (await directory.exists()) {
      await directory.delete(recursive: true);
    }
  });

  test('missing settings file returns defaults', () async {
    final AppSettingsStore store = AppSettingsStore(directory: directory);
    expect(await store.load(), AppSettings.defaults);
  });

  test('settings round-trip through the local JSON file', () async {
    final AppSettingsStore store = AppSettingsStore(directory: directory);
    const AppSettings custom = AppSettings(
      apiBaseUrl: 'http://127.0.0.1:9999',
      pollingIntervalSeconds: 5,
      reduceMotion: true,
      density: AuraDensity.compact,
    );

    await store.save(custom);
    expect(await store.load(), custom);

    final File file = File(
      '${directory.path}${Platform.pathSeparator}app_settings.json',
    );
    expect(await file.exists(), isTrue);
    expect(await file.readAsString(), contains('127.0.0.1:9999'));
  });

  test('corrupt settings file falls back to defaults', () async {
    final AppSettingsStore store = AppSettingsStore(directory: directory);
    final File file = File(
      '${directory.path}${Platform.pathSeparator}app_settings.json',
    );
    await file.writeAsString('not json');
    expect(await store.load(), AppSettings.defaults);
  });

  test('controller update persists and reset restores defaults', () async {
    final AppSettingsStore store = AppSettingsStore(directory: directory);
    final AppSettingsController controller =
        AppSettingsController(store: store);
    addTearDown(controller.dispose);

    await controller.load();
    expect(controller.state, AppSettings.defaults);

    await controller.update(
      const AppSettings(
        apiBaseUrl: 'http://localhost:8765/',
        pollingIntervalSeconds: 10,
      ),
    );
    expect(controller.state.apiBaseUrl, 'http://localhost:8765');
    expect(controller.state.pollingIntervalSeconds, 10);

    // A fresh controller must read what the previous one wrote.
    final AppSettingsController reloaded = AppSettingsController(store: store);
    addTearDown(reloaded.dispose);
    await reloaded.load();
    expect(reloaded.state.apiBaseUrl, 'http://localhost:8765');
    expect(reloaded.state.pollingIntervalSeconds, 10);

    await reloaded.reset();
    expect(reloaded.state, AppSettings.defaults);
    expect(await store.load(), AppSettings.defaults);
  });
}
