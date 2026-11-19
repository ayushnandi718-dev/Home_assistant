import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_controller.dart';
import 'package:aura_hub/core/settings/app_settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 4 app-wide preference model', () {
    test('dark is the default theme and language follows the system', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.themeMode, AuraThemeMode.dark);
      expect(settings.themeMode.themeMode, ThemeMode.dark);
      expect(settings.language, AuraLanguage.auto);
      expect(settings.language.locale, isNull);

      expect(AuraThemeMode.light.themeMode, ThemeMode.light);
      expect(AuraThemeMode.system.themeMode, ThemeMode.system);
      expect(AuraLanguage.english.locale, const Locale('en'));
      expect(AuraLanguage.hindi.locale, const Locale('hi'));
      expect(AuraLanguage.bengali.locale, const Locale('bn'));
    });

    test('startup and telemetry preferences have conservative defaults', () {
      const AppSettings settings = AppSettings.defaults;
      expect(settings.telemetryEnabled, isTrue);
      expect(settings.launchAtStartup, isFalse);
      expect(settings.startMinimized, isFalse);
      expect(settings.rememberLastProfile, isFalse);
      expect(settings.lastActiveProfile, isNull);
    });

    test('only the two real profile scopes can be remembered', () {
      expect(AppSettings.normaliseProfileScope('ayush'), 'ayush');
      expect(AppSettings.normaliseProfileScope('family'), 'family');
      expect(AppSettings.normaliseProfileScope('root'), isNull);
      expect(AppSettings.normaliseProfileScope(''), isNull);
      expect(AppSettings.normaliseProfileScope(7), isNull);
    });
  });

  group('Phase 4 settings persistence', () {
    late Directory directory;
    late AppSettingsStore store;
    late File file;

    setUp(() async {
      directory =
          await Directory.systemTemp.createTemp('aura_phase4_settings_');
      store = AppSettingsStore(directory: directory);
      file = File(
        '${directory.path}${Platform.pathSeparator}app_settings.json',
      );
    });

    tearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });

    test('every new preference survives a restart', () async {
      const AppSettings custom = AppSettings(
        themeMode: AuraThemeMode.light,
        language: AuraLanguage.hindi,
        telemetryEnabled: false,
        launchAtStartup: true,
        startMinimized: true,
        rememberLastProfile: true,
        lastActiveProfile: 'ayush',
      );
      await store.save(custom);

      final AppSettings reloaded =
          await AppSettingsStore(directory: directory).load();
      expect(reloaded, custom);
      expect(reloaded.themeMode, AuraThemeMode.light);
      expect(reloaded.language.locale, const Locale('hi'));
      expect(reloaded.telemetryEnabled, isFalse);
    });

    test('future schemas and corrupt JSON fall back to defaults', () async {
      await file.writeAsString(
        '{"schema":${AppSettings.schemaVersion + 1},'
        '"themeMode":"light","launchAtStartup":true}',
      );
      expect(await store.load(), AppSettings.defaults);

      await file.writeAsString('{not json');
      expect(await store.load(), AppSettings.defaults);
    });

    test('unknown enum values, bad types and invalid scopes fall back safely',
        () async {
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'schema': AppSettings.schemaVersion,
        'themeMode': 'neon',
        'language': 'klingon',
        'telemetryEnabled': 'yes',
        'launchAtStartup': 1,
        'startMinimized': <String>[],
        'rememberLastProfile': 'true',
        'lastActiveProfile': 'root',
      }));

      final AppSettings loaded = await store.load();
      expect(loaded.themeMode, AuraThemeMode.dark);
      expect(loaded.language, AuraLanguage.auto);
      expect(loaded.telemetryEnabled, isTrue);
      expect(loaded.launchAtStartup, isFalse);
      expect(loaded.startMinimized, isFalse);
      expect(loaded.rememberLastProfile, isFalse);
      expect(loaded.lastActiveProfile, isNull);
    });

    test('controller canonicalises remembered scope and reset clears it',
        () async {
      final AppSettingsController controller =
          AppSettingsController(store: store);
      addTearDown(controller.dispose);
      await controller.load();

      await controller.update(
        const AppSettings(rememberLastProfile: true, lastActiveProfile: 'root'),
      );
      expect(controller.state.lastActiveProfile, isNull);

      await controller.update(
        controller.state.copyWith(lastActiveProfile: 'ayush'),
      );
      expect(controller.state.lastActiveProfile, 'ayush');
      expect((await store.load()).lastActiveProfile, 'ayush');

      await controller.reset();
      expect(controller.state, AppSettings.defaults);
      expect(await store.load(), AppSettings.defaults);
    });
  });
}
