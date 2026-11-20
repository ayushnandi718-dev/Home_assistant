import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/services/clock_service.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_controller.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/display/data/display_preferences_store.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:aura_hub/features/display/presentation/display_studio_page.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase3_test_helpers.dart';

/// A system-clock subtype whose time can be advanced deterministically. It is
/// recognised as "live" by the preview, so the sweep animation is exercised.
class _TickingClock extends SystemAuraClock {
  _TickingClock(this._current);

  DateTime _current;

  void advance(Duration duration) => _current = _current.add(duration);

  @override
  DateTime nowDeviceLocal() => _current;
}

void main() {
  group('Display preferences persistence', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_phase3_store_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('round trips every display preference', () async {
      final DisplayPreferencesStore store = DisplayPreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      const DisplayPreferences preferences = DisplayPreferences(
        brightness: 33,
        screenTimeout: ScreenTimeout.seconds30,
        sleepSchedule: SleepSchedule(
          enabled: true,
          startMinutes: 1350,
          endMinutes: 390,
        ),
        panelTheme: PanelTheme.mint,
        wallpaper: PanelWallpaper.neon,
        clockStyle: ClockStyle.ring,
        watchFace: PanelWatchFace.pulse,
        orientation: PanelOrientation.landscape,
      );

      expect(await store.save(preferences), isTrue);
      expect(await store.load(), preferences);

      final Object? decoded =
          jsonDecode(File(store.filePath).readAsStringSync());
      expect(decoded, isA<Map<String, dynamic>>());
      final Map<String, dynamic> json = decoded! as Map<String, dynamic>;
      expect(json['wallpaper'], 'neon');
      expect(json['clockStyle'], 'ring');
      expect(json['watchFace'], 'pulse');
    });

    test('corrupt data falls back safely and values are clamped', () async {
      final DisplayPreferencesStore store = DisplayPreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(store.filePath);
      file.writeAsStringSync('{not valid json');
      expect(await store.load(), DisplayPreferences.defaults);

      file.writeAsStringSync(jsonEncode(<String, dynamic>{
        'brightness': 999,
        'wallpaper': 'does-not-exist',
        'watchFace': 'does-not-exist',
        'sleepSchedule': <String, dynamic>{
          'enabled': true,
          'startMinutes': 9999,
          'endMinutes': -4,
        },
      }));
      final DisplayPreferences loaded = await store.load();
      expect(loaded.brightness, DisplayPreferences.maxBrightness);
      expect(loaded.wallpaper, PanelWallpaper.aurora);
      expect(loaded.watchFace, PanelWatchFace.classic);
      // Sleep minutes normalize to UI-supported 30-minute increments [0, 1410].
      expect(loaded.sleepSchedule.startMinutes, 1410);
      expect(loaded.sleepSchedule.endMinutes, 0);
    });

    test('sleep minutes normalize to valid 30-minute UI increments', () async {
      final DisplayPreferencesStore store = DisplayPreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(store.filePath);

      DisplayPreferences loadWithSchedule(Object? schedule) {
        file.writeAsStringSync(jsonEncode(<String, dynamic>{
          'sleepSchedule': schedule,
        }));
        return DisplayPreferences.fromJson(jsonDecode(file.readAsStringSync()));
      }

      // Valid 30-minute values and zero.
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': 0, 'endMinutes': 30})
              .sleepSchedule
              .startMinutes,
          0);
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': 0, 'endMinutes': 30})
              .sleepSchedule
              .endMinutes,
          30);
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': 1410, 'endMinutes': 0})
              .sleepSchedule
              .startMinutes,
          1410);

      // Off-step values round to nearest 30-minute increment.
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': 17, 'endMinutes': 44})
              .sleepSchedule
              .startMinutes,
          30);
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': 17, 'endMinutes': 44})
              .sleepSchedule
              .endMinutes,
          30);
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': 14, 'endMinutes': 46})
              .sleepSchedule
              .startMinutes,
          0);
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': 14, 'endMinutes': 46})
              .sleepSchedule
              .endMinutes,
          60);

      // Negative and beyond range clamp to supported bounds.
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': -30, 'endMinutes': 2000})
              .sleepSchedule
              .startMinutes,
          0);
      expect(
          loadWithSchedule(
                  <String, dynamic>{'startMinutes': -30, 'endMinutes': 2000})
              .sleepSchedule
              .endMinutes,
          1410);

      // Missing, null, wrong types, and malformed schedule fall back safely.
      expect(
          loadWithSchedule(<String, dynamic>{'enabled': true})
              .sleepSchedule
              .startMinutes,
          SleepSchedule.defaultStartMinutes);
      expect(
          loadWithSchedule(<String, dynamic>{
            'startMinutes': null,
            'endMinutes': '22:00'
          }).sleepSchedule.startMinutes,
          SleepSchedule.defaultStartMinutes);
      expect(
          loadWithSchedule(<String, dynamic>{
            'startMinutes': null,
            'endMinutes': '22:00'
          }).sleepSchedule.endMinutes,
          SleepSchedule.defaultEndMinutes);
      expect(
          loadWithSchedule('not-a-map').sleepSchedule, const SleepSchedule());

      // Corrupt JSON remains safe.
      file.writeAsStringSync('{broken');
      expect(await store.load(), DisplayPreferences.defaults);
    });

    test('AYUSH and FAMILY use different files', () {
      final DisplayPreferencesStore family = DisplayPreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final DisplayPreferencesStore ayush = DisplayPreferencesStore(
        directory: directory,
        profile: AuraProfile.ayush,
      );
      expect(family.filePath, isNot(ayush.filePath));
      expect(family.filePath, contains('display_preferences_family.json'));
      expect(ayush.filePath, contains('display_preferences_ayush.json'));
    });
  });

  group('Display Studio UI', () {
    late Directory directory;
    late Map<AuraProfile, MemoryDisplayStore> displayStores;
    late Map<AuraProfile, MemoryLayoutStore> layoutStores;
    late MemoryAppSettingsStore settingsStore;
    late ProviderContainer container;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_phase3_ui_');
      displayStores = <AuraProfile, MemoryDisplayStore>{
        for (final AuraProfile profile in AuraProfile.values)
          profile: MemoryDisplayStore(directory, profile),
      };
      layoutStores = <AuraProfile, MemoryLayoutStore>{
        for (final AuraProfile profile in AuraProfile.values)
          profile: MemoryLayoutStore(directory, profile),
      };
      settingsStore = MemoryAppSettingsStore(directory);
      container = ProviderContainer(
        overrides: <Override>[
          displayPreferencesForProvider.overrideWith(
            (Ref ref, AuraProfile profile) => DisplayPreferencesController(
              store: displayStores[profile]!,
            ),
          ),
          dashboardLayoutForProvider.overrideWith(
            (Ref ref, AuraProfile profile) => DashboardLayoutController(
              store: layoutStores[profile]!,
            ),
          ),
          appSettingsProvider.overrideWith(
            (Ref ref) => AppSettingsController(store: settingsStore),
          ),
          displayClockProvider.overrideWithValue(
            FixedAuraClock(
              DateTime.utc(2026, 11, 20, 4, 39, 9),
              deviceTimeZoneName: 'IST',
              deviceUtcOffset: Duration(hours: 5, minutes: 30),
            ),
          ),
        ],
      );
    });

    tearDown(() {
      container.dispose();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    Future<void> pumpPage(WidgetTester tester) async {
      // A tall viewport keeps every control hit-testable without scrolling;
      // the wide layout is still exercised because the width is 1440.
      tester.view.physicalSize = const Size(1440, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: DisplayStudioPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders real controls and honest availability states',
        (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('Display Studio'), findsOneWidget);
      expect(find.text('Brightness, timeout & sleep'), findsOneWidget);
      expect(find.text('Theme, wallpaper & clock'), findsOneWidget);
      expect(find.text('Dashboard widgets'), findsOneWidget);
      expect(find.text('Orientation & saved state'), findsOneWidget);
      expect(find.text('Local panel preview'), findsOneWidget);
      for (final String label in <String>[
        'Configured',
        'Preview only',
        'Available on this computer',
        'Requires AURA hardware',
        'Not implemented',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(find.textContaining('PLANNED'), findsNothing);
      expect(find.text('Foundation build'), findsNothing);
      expect(find.byType(Slider), findsOneWidget);
      expect(find.text('10:09:09'), findsOneWidget);
      expect(find.text('Fri, 20 Nov 2026'), findsOneWidget);
      expect(find.textContaining('IST · UTC+05:30'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('brightness slider changes the saved preference and preview',
        (WidgetTester tester) async {
      await pumpPage(tester);

      final int before = container.read(displayPreferencesProvider).brightness;
      await tester.drag(find.byType(Slider).first, const Offset(100, 0));
      await tester.pumpAndSettle();

      final int after = container.read(displayPreferencesProvider).brightness;
      expect(after, isNot(before));
      expect(displayStores[AuraProfile.family]!.value.brightness, after);
      expect(displayStores[AuraProfile.family]!.saveCount, greaterThan(0));
      expect(find.textContaining('$after%'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('wallpaper and clock selections change the local preview',
        (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('Dusk'));
      await tester.pumpAndSettle();
      expect(
        container.read(displayPreferencesProvider).wallpaper,
        PanelWallpaper.dusk,
      );
      expect(find.textContaining('Dusk'), findsWidgets);

      // SegmentedButton inflates its own buttons; ButtonSegment is only a
      // configuration object, so tap the rendered label instead.
      await tester.tap(find.text('Analog'));
      await tester.pumpAndSettle();
      expect(
        container.read(displayPreferencesProvider).clockStyle,
        ClockStyle.analog,
      );
      expect(displayStores[AuraProfile.family]!.saveCount, 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('new wallpaper, clock and watch face variants persist',
        (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('Neon'));
      await tester.pumpAndSettle();
      expect(
        container.read(displayPreferencesProvider).wallpaper,
        PanelWallpaper.neon,
      );
      expect(find.textContaining('Neon'), findsWidgets);

      await tester.tap(find.text('Ring'));
      await tester.pumpAndSettle();
      expect(
        container.read(displayPreferencesProvider).clockStyle,
        ClockStyle.ring,
      );

      await tester.tap(find.text('Pulse'));
      await tester.pumpAndSettle();
      expect(
        container.read(displayPreferencesProvider).watchFace,
        PanelWatchFace.pulse,
      );

      expect(displayStores[AuraProfile.family]!.saveCount, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('application theme selection updates the real app setting',
        (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.byType(DropdownButton<AuraThemeMode>));
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(DropdownMenuItem<AuraThemeMode>, 'Light'),
      );
      await tester.pumpAndSettle();

      expect(
          container.read(appSettingsProvider).themeMode, AuraThemeMode.light);
      expect(settingsStore.value.themeMode, AuraThemeMode.light);
      expect(tester.takeException(), isNull);
    });

    testWidgets('widget studio edits the active dashboard layout',
        (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('6 of 6 widgets visible.'), findsNothing);
      expect(find.textContaining('6 of 6 widgets visible'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Open widget studio'),
      );
      await tester.pumpAndSettle();
      expect(find.text('WIDGET STUDIO'), findsOneWidget);

      await tester.tap(find.byTooltip('Hide widget').first);
      await tester.pumpAndSettle();
      expect(
        container
            .read(dashboardLayoutProvider)
            .isVisible(DashboardWidgetId.overview),
        isFalse,
      );
      expect(layoutStores[AuraProfile.family]!.saveCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports an unsuccessful preference write',
        (WidgetTester tester) async {
      displayStores[AuraProfile.family]!.failSaves = true;
      await pumpPage(tester);

      await tester.drag(find.byType(Slider).first, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(find.text('Could not save locally'), findsWidgets);
      expect(find.text('Saved locally'), findsNothing);
    });

    testWidgets('switching workspace swaps display preferences',
        (WidgetTester tester) async {
      await pumpPage(tester);
      final int familySaves = displayStores[AuraProfile.family]!.saveCount;

      container.read(profileSessionProvider.notifier).state = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime.now(),
        authenticated: true,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('AYUSH workspace'), findsWidgets);

      await tester.drag(find.byType(Slider).first, const Offset(-60, 0));
      await tester.pumpAndSettle();

      expect(displayStores[AuraProfile.family]!.saveCount, familySaves);
      // A drag emits several onChanged events, each of which persists.
      expect(displayStores[AuraProfile.ayush]!.saveCount, greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('normalized sleep minutes are shown by UI dropdowns',
        (WidgetTester tester) async {
      // Simulate an off-step/on-disk-invalid value normalized at load.
      displayStores[AuraProfile.family]!.value = DisplayPreferences.fromJson(
        <String, dynamic>{
          'sleepSchedule': <String, dynamic>{
            'enabled': true,
            'startMinutes': 17,
            'endMinutes': 2000,
          },
        },
      );

      await pumpPage(tester);
      await container
          .read(displayPreferencesForProvider(AuraProfile.family).notifier)
          .load();
      await tester.pumpAndSettle();

      final List<DropdownButton<int>> dropdowns = tester
          .widgetList<DropdownButton<int>>(find.byType(DropdownButton<int>))
          .toList();
      expect(dropdowns.length, greaterThanOrEqualTo(2));
      expect(dropdowns[0].value, 30); // 17 -> nearest 30-minute step
      expect(dropdowns[1].value, 1410); // 2000 -> clamped to max UI step
      expect(find.text('00:30'), findsWidgets);
      expect(find.text('23:30'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('analog preview reads the live clock and updates each second',
        (WidgetTester tester) async {
      final _TickingClock clock = _TickingClock(
        DateTime(2026, 11, 20, 10, 9, 9),
      );
      displayStores[AuraProfile.family]!.value = DisplayPreferences.defaults
          .copyWith(clockStyle: ClockStyle.analog);
      final ProviderContainer liveContainer = ProviderContainer(
        overrides: <Override>[
          displayPreferencesForProvider.overrideWith(
            (Ref ref, AuraProfile profile) => DisplayPreferencesController(
              store: displayStores[profile]!,
            ),
          ),
          dashboardLayoutForProvider.overrideWith(
            (Ref ref, AuraProfile profile) => DashboardLayoutController(
              store: layoutStores[profile]!,
            ),
          ),
          appSettingsProvider.overrideWith(
            (Ref ref) => AppSettingsController(store: settingsStore),
          ),
          displayClockProvider.overrideWithValue(clock),
        ],
      );
      addTearDown(liveContainer.dispose);
      await liveContainer
          .read(displayPreferencesForProvider(AuraProfile.family).notifier)
          .load();

      tester.view.physicalSize = const Size(1440, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: liveContainer,
          child: const MaterialApp(
            home: Scaffold(body: DisplayStudioPage()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('10:09:09'), findsOneWidget);
      // The live clock starts a repeating sweep; fixed test clocks do not.
      expect(find.byType(AnimatedBuilder), findsWidgets);

      clock.advance(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('10:09:10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
