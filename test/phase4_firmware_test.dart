import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/firmware/data/firmware_update_preferences_store.dart';
import 'package:aura_hub/features/firmware/domain/firmware_update_preferences.dart';
import 'package:aura_hub/features/firmware/presentation/firmware_page.dart';
import 'package:aura_hub/features/firmware/presentation/firmware_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Deterministic file reader so digest tests never depend on real I/O.
class MemoryFirmwareFileReader {
  List<int> bytes = const <int>[1, 2, 3];
  bool fail = false;

  Future<List<int>> read(String path) async {
    if (fail) throw StateError('Unreadable test file: $path');
    return bytes;
  }
}

/// In-memory store so widget tests exercise the real controller without
/// touching the app-data directory.
class MemoryFirmwareStore extends FirmwareUpdatePreferencesStore {
  MemoryFirmwareStore(Directory directory, AuraProfile profile)
      : super(directory: directory, profile: profile);

  FirmwareUpdatePreferences value = FirmwareUpdatePreferences.defaults;
  int saveCount = 0;
  bool failSaves = false;

  @override
  Future<FirmwareUpdatePreferences> load() async => value;

  @override
  Future<bool> save(FirmwareUpdatePreferences preferences) async {
    if (failSaves) return false;
    value = preferences;
    saveCount++;
    return true;
  }
}

void main() {
  group('Firmware preferences persistence', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_firmware_store_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('round trips every firmware preference', () async {
      final FirmwareUpdatePreferencesStore store =
          FirmwareUpdatePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      const FirmwareUpdatePreferences preferences = FirmwareUpdatePreferences(
        channel: FirmwareChannel.beta,
        autoCheckEnabled: true,
        requireVerification: false,
      );

      expect(await store.save(preferences), isTrue);
      expect(await store.load(), preferences);

      final Object? decoded =
          jsonDecode(File(store.filePath).readAsStringSync());
      expect(decoded, isA<Map<String, dynamic>>());
      final Map<String, dynamic> json = decoded! as Map<String, dynamic>;
      expect(json['version'], 1);
      expect(json['channel'], 'beta');
      expect(json['autoCheckEnabled'], isTrue);
      expect(json['requireVerification'], isFalse);
    });

    test('corrupt unknown data falls back to conservative defaults', () async {
      final FirmwareUpdatePreferencesStore store =
          FirmwareUpdatePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(store.filePath);

      file.writeAsStringSync('{not valid json');
      expect(await store.load(), FirmwareUpdatePreferences.defaults);

      file.writeAsStringSync(jsonEncode(<String, dynamic>{
        'channel': 'canary',
        'autoCheckEnabled': 'yes',
        'requireVerification': 'no',
      }));
      expect(await store.load(), FirmwareUpdatePreferences.defaults);

      file.writeAsStringSync(jsonEncode(<int>[1, 2, 3]));
      expect(await store.load(), FirmwareUpdatePreferences.defaults);
    });

    test('AYUSH and FAMILY use different files', () {
      final FirmwareUpdatePreferencesStore family =
          FirmwareUpdatePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final FirmwareUpdatePreferencesStore ayush =
          FirmwareUpdatePreferencesStore(
        directory: directory,
        profile: AuraProfile.ayush,
      );

      expect(family.filePath, isNot(ayush.filePath));
      expect(
        family.filePath,
        contains('firmware_update_preferences_family.json'),
      );
      expect(
        ayush.filePath,
        contains('firmware_update_preferences_ayush.json'),
      );
    });
  });

  group('Firmware Update UI', () {
    late Directory directory;
    late Map<AuraProfile, MemoryFirmwareStore> firmwareStores;
    late MemoryFirmwareFileReader fileReader;
    late ProviderContainer container;

    setUp(() async {
      directory = Directory.systemTemp.createTempSync('aura_firmware_ui_');
      fileReader = MemoryFirmwareFileReader();
      firmwareStores = <AuraProfile, MemoryFirmwareStore>{
        for (final AuraProfile profile in AuraProfile.values)
          profile: MemoryFirmwareStore(directory, profile),
      };
      container = ProviderContainer(
        overrides: <Override>[
          firmwareUpdatePreferencesForProvider.overrideWith(
            (Ref ref, AuraProfile profile) =>
                FirmwareUpdatePreferencesController(
              store: firmwareStores[profile]!,
            ),
          ),
          firmwareFileReaderProvider.overrideWithValue(fileReader.read),
        ],
      );
      for (final AuraProfile profile in AuraProfile.values) {
        await container
            .read(firmwareUpdatePreferencesForProvider(profile).notifier)
            .load();
      }
    });

    tearDown(() {
      container.dispose();
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    Future<void> pumpPage(WidgetTester tester) async {
      // Tall viewport keeps every control hit-testable; 1440 still exercises
      // the wide two-column layout.
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
            home: Scaffold(body: FirmwarePage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders honest configuration-only states',
        (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('Firmware & Updates'), findsOneWidget);
      expect(find.text('Update preferences'), findsOneWidget);
      expect(find.text('Update readiness'), findsOneWidget);
      expect(find.text('Release status'), findsOneWidget);
      expect(find.text('Recovery & verification'), findsOneWidget);
      expect(find.text('Local file digest'), findsOneWidget);
      for (final String label in <String>[
        'Configured',
        'Preview only',
        'Available on this computer',
        'Requires AURA hardware',
        'Not implemented',
      ]) {
        expect(find.text(label), findsWidgets, reason: label);
      }
      expect(
        find.text('No device connected — no update can run'),
        findsOneWidget,
      );
      expect(
        find.text('Unavailable — no device connected'),
        findsOneWidget,
      );
      expect(find.text('Unavailable — no release service'), findsOneWidget);
      expect(find.text('No update in progress'), findsOneWidget);
      expect(find.text('No install recorded in this build'), findsOneWidget);
      expect(find.textContaining('PLANNED'), findsNothing);
      expect(find.text('Foundation build'), findsNothing);

      // No fake progress or success state can be reached from this page.
      expect(find.textContaining('Update complete'), findsNothing);
      expect(find.textContaining('Install succeeded'), findsNothing);
      expect(find.textContaining('Update successful'), findsNothing);
      expect(find.textContaining('Download complete'), findsNothing);
      expect(find.textContaining('%'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('preference changes are saved locally',
        (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(
        container.read(firmwareUpdatePreferencesProvider).channel,
        FirmwareChannel.beta,
      );
      expect(firmwareStores[AuraProfile.family]!.saveCount, 1);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(
        container.read(firmwareUpdatePreferencesProvider).autoCheckEnabled,
        isTrue,
      );

      await tester.tap(find.byType(Switch).last);
      await tester.pumpAndSettle();
      expect(
        container.read(firmwareUpdatePreferencesProvider).requireVerification,
        isFalse,
      );

      expect(firmwareStores[AuraProfile.family]!.saveCount, 3);
      expect(
        firmwareStores[AuraProfile.family]!.value,
        const FirmwareUpdatePreferences(
          channel: FirmwareChannel.beta,
          autoCheckEnabled: true,
          requireVerification: false,
        ),
      );
      expect(find.text('Saved locally'), findsOneWidget);
      expect(find.text('Could not save locally'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reset restores defaults and persists them',
        (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(firmwareStores[AuraProfile.family]!.saveCount, 2);

      await tester.tap(find.text('Reset saved firmware preferences'));
      await tester.pumpAndSettle();

      expect(
        container.read(firmwareUpdatePreferencesProvider),
        FirmwareUpdatePreferences.defaults,
      );
      expect(firmwareStores[AuraProfile.family]!.value,
          FirmwareUpdatePreferences.defaults);
      expect(firmwareStores[AuraProfile.family]!.saveCount, 3);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports an unsuccessful local save',
        (WidgetTester tester) async {
      firmwareStores[AuraProfile.family]!.failSaves = true;
      await pumpPage(tester);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();

      expect(find.text('Could not save locally'), findsOneWidget);
      expect(find.text('Saved locally'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('switching workspace swaps firmware preferences',
        (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.tap(find.text('Beta'));
      await tester.pumpAndSettle();
      expect(firmwareStores[AuraProfile.family]!.value.channel,
          FirmwareChannel.beta);

      container.read(profileSessionProvider.notifier).state = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime.now(),
        authenticated: true,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('AYUSH workspace'), findsWidgets);

      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();

      expect(firmwareStores[AuraProfile.ayush]!.saveCount, 1);
      expect(firmwareStores[AuraProfile.ayush]!.value.autoCheckEnabled, isTrue);
      expect(
        firmwareStores[AuraProfile.family]!.value.autoCheckEnabled,
        isFalse,
      );
      expect(firmwareStores[AuraProfile.family]!.saveCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('computes a local SHA-256 without claiming verification',
        (WidgetTester tester) async {
      fileReader.bytes = const <int>[1, 2, 3];
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), 'local_firmware.bin');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Compute local SHA-256'),
      );
      await tester.pumpAndSettle();

      expect(
        find.text(
          '039058c6f2c0cb492c533b0a4d14ef77cc0f78abccced5287d84a1a2011cfb81',
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining('not integrity or authenticity verification'),
        findsOneWidget,
      );
      expect(find.textContaining('Verification successful'), findsNothing);
      expect(find.textContaining('Firmware verified'), findsNothing);
      expect(find.textContaining('Install successful'), findsNothing);
      expect(find.textContaining('Firmware installed'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reports an unreadable local file without a digest',
        (WidgetTester tester) async {
      fileReader.fail = true;
      await pumpPage(tester);

      await tester.enterText(find.byType(TextField), 'missing_firmware.bin');
      await tester.tap(
        find.widgetWithText(FilledButton, 'Compute local SHA-256'),
      );
      await tester.pumpAndSettle();

      expect(find.text('Computing…'), findsNothing);
      expect(
          find.text('Could not read that file. Check the path and try again.'),
          findsOneWidget);
      expect(find.textContaining('039058c6f2c0cb'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });
}
