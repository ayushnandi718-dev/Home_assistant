import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/voice_audio/data/voice_preferences_store.dart';
import 'package:aura_hub/features/voice_audio/domain/microphone_probe.dart';
import 'package:aura_hub/features/voice_audio/domain/voice_preferences.dart';
import 'package:aura_hub/features/voice_audio/presentation/voice_audio_page.dart';
import 'package:aura_hub/features/voice_audio/presentation/voice_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'phase3_test_helpers.dart';

void main() {
  group('Voice preferences persistence', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_phase3_vstore_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('round trips every voice preference', () async {
      final VoicePreferencesStore store = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      const VoicePreferences preferences = VoicePreferences(
        wakePhraseEnabled: true,
        microphoneEnabled: true,
        language: VoiceLanguage.bengali,
        verbosity: VoiceVerbosity.detailed,
        speed: VoiceSpeed.fast,
        confirmation: VoiceConfirmation.spoken,
        output: AudioOutputPreference.auraPanel,
        volume: 25,
      );

      expect(await store.save(preferences), isTrue);
      expect(await store.load(), preferences);
      expect(preferences.voiceInputRequested, isTrue);
      expect(preferences.responsePreview, contains('AURA প্রস্তুত।'));
      expect(jsonDecode(File(store.filePath).readAsStringSync()),
          isA<Map<String, dynamic>>());
    });

    test('corrupt data falls back safely and volume is clamped', () async {
      final VoicePreferencesStore store = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(store.filePath);
      file.writeAsStringSync('not json at all');
      expect(await store.load(), VoicePreferences.defaults);

      file.writeAsStringSync(jsonEncode(<String, dynamic>{
        'volume': 500,
        'language': 'klingon',
        'microphoneEnabled': true,
      }));
      final VoicePreferences loaded = await store.load();
      expect(loaded.volume, VoicePreferences.maxVolume);
      expect(loaded.language, VoiceLanguage.english);
      expect(loaded.microphoneEnabled, isTrue);
      expect(loaded.wakePhraseEnabled, isFalse);
    });

    test('AYUSH and FAMILY use different files', () {
      final VoicePreferencesStore family = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final VoicePreferencesStore ayush = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.ayush,
      );
      expect(family.filePath, isNot(ayush.filePath));
      expect(family.filePath, contains('voice_preferences_family.json'));
      expect(ayush.filePath, contains('voice_preferences_ayush.json'));
    });

    test('schema version: current and missing legacy load safely', () async {
      final VoicePreferencesStore store = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(store.filePath);

      file.writeAsStringSync(jsonEncode(<String, dynamic>{
        'version': 1,
        'microphoneEnabled': true,
        'language': 'hindi',
        'volume': 42,
      }));
      var result = await store.loadWithStatus();
      expect(result.hasControlledError, isFalse);
      expect(result.writeProtected, isFalse);
      expect(result.preferences.microphoneEnabled, isTrue);
      expect(result.preferences.language, VoiceLanguage.hindi);
      expect(result.preferences.volume, 42);

      // Missing version is accepted as legacy v1 for backward compatibility.
      file.writeAsStringSync(jsonEncode(<String, dynamic>{
        'wakePhraseEnabled': true,
        'verbosity': 'detailed',
        'volume': 15,
      }));
      result = await store.loadWithStatus();
      expect(result.hasControlledError, isFalse);
      expect(result.writeProtected, isFalse);
      expect(result.preferences.wakePhraseEnabled, isTrue);
      expect(result.preferences.verbosity, VoiceVerbosity.detailed);
      expect(result.preferences.volume, 15);
    });

    test(
        'schema version: invalid/null/string/negative/zero are controlled errors',
        () async {
      final VoicePreferencesStore store = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(store.filePath);

      for (final Object? badVersion in <Object?>[
        null,
        '1',
        '2',
        -1,
        0,
        1.5,
        true,
      ]) {
        final String raw = jsonEncode(<String, dynamic>{
          'version': badVersion,
          'microphoneEnabled': true,
          'volume': 10,
        });
        file.writeAsStringSync(raw);
        final VoicePreferencesLoadResult result = await store.loadWithStatus();
        expect(result.preferences, VoicePreferences.defaults,
            reason: 'version=$badVersion');
        expect(result.writeProtected, isTrue, reason: 'version=$badVersion');
        expect(result.error, isA<InvalidVoicePreferencesSchemaException>(),
            reason: 'version=$badVersion');
        // Original file is preserved (no automatic overwrite).
        expect(file.readAsStringSync(), raw, reason: 'version=$badVersion');
      }
    });

    test(
        'schema version: unsupported future version is preserved and protected',
        () async {
      final VoicePreferencesStore store = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(store.filePath);
      final String raw = jsonEncode(<String, dynamic>{
        'version': 2,
        'microphoneEnabled': true,
        'language': 'hindi',
        'futureField': 'keep-me',
      });
      file.writeAsStringSync(raw);

      final VoicePreferencesLoadResult result = await store.loadWithStatus();
      expect(result.preferences, VoicePreferences.defaults);
      expect(result.writeProtected, isTrue);
      expect(
        result.error,
        isA<UnsupportedFutureVoicePreferencesSchemaException>(),
      );
      expect(
        (result.error! as UnsupportedFutureVoicePreferencesSchemaException)
            .version,
        2,
      );
      // Do not overwrite unsupported future-version files with defaults.
      expect(file.readAsStringSync(), raw);
      expect(await store.save(VoicePreferences.defaults), isTrue);
      // Explicit save remains possible via store API, but controller/load paths
      // must not auto-overwrite; file content after explicit save is valid v1.
      expect(jsonDecode(file.readAsStringSync())['version'], 1);
    });

    test('malformed JSON is a safe controlled fallback', () async {
      final VoicePreferencesStore store = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final File file = File(store.filePath);
      file.writeAsStringSync('{not json');
      final VoicePreferencesLoadResult result = await store.loadWithStatus();
      expect(result.preferences, VoicePreferences.defaults);
      expect(result.hasControlledError, isTrue);
      // Malformed content is not auto-overwritten.
      expect(file.readAsStringSync(), '{not json');
    });

    test('version handling and save/reload are isolated per profile', () async {
      final VoicePreferencesStore family = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.family,
      );
      final VoicePreferencesStore ayush = VoicePreferencesStore(
        directory: directory,
        profile: AuraProfile.ayush,
      );

      await family.save(const VoicePreferences(
        language: VoiceLanguage.bengali,
        volume: 21,
      ));
      File(ayush.filePath).writeAsStringSync(jsonEncode(<String, dynamic>{
        'version': 99,
        'volume': 10,
      }));

      final VoicePreferences familyLoaded = await family.load();
      final VoicePreferencesLoadResult ayushLoaded =
          await ayush.loadWithStatus();

      expect(familyLoaded.language, VoiceLanguage.bengali);
      expect(familyLoaded.volume, 21);
      expect(ayushLoaded.writeProtected, isTrue);
      expect(ayushLoaded.error,
          isA<UnsupportedFutureVoicePreferencesSchemaException>());
      expect(File(family.filePath).existsSync(), isTrue);
      expect(File(ayush.filePath).existsSync(), isTrue);
      expect(
          jsonDecode(File(ayush.filePath).readAsStringSync())['version'], 99);
    });
  });

  group('Microphone honesty', () {
    test('desktop probe refuses to guess permission or device state', () async {
      final MicrophoneStatus status =
          await const DesktopMicrophoneProbe().probe();
      expect(status.captureSupported, isFalse);
      expect(status.permission, MicrophonePermissionStatus.unknown);
      expect(status.device, MicrophoneDeviceStatus.unknown);
      expect(status.message, contains('no microphone capture plugin'));
      expect(status.permissionLabel, 'Not queryable in this build');
    });
  });

  group('Voice & Audio UI', () {
    late Directory directory;
    late Map<AuraProfile, MemoryVoiceStore> voiceStores;
    late ProviderContainer container;
    late MicrophoneProbe probe;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_phase3_vui_');
      voiceStores = <AuraProfile, MemoryVoiceStore>{
        for (final AuraProfile profile in AuraProfile.values)
          profile: MemoryVoiceStore(directory, profile),
      };
      probe = const DesktopMicrophoneProbe();
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
      // One container owns the stores *and* the probe. A parent/child split
      // would leave microphoneStatusProvider in the parent while its dependency
      // is overridden in the child, which Riverpod rejects.
      container = ProviderContainer(
        overrides: <Override>[
          voicePreferencesForProvider.overrideWith(
            (Ref ref, AuraProfile profile) => VoicePreferencesController(
              store: voiceStores[profile]!,
            ),
          ),
          microphoneProbeProvider.overrideWithValue(probe),
        ],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: VoiceAudioPage()),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders real controls and honest availability states',
        (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('Voice & Audio'), findsOneWidget);
      expect(find.text('Wake phrase & microphone'), findsOneWidget);
      expect(find.text('Languages'), findsOneWidget);
      expect(find.text('Voice responses'), findsOneWidget);
      expect(find.text('Output & volume'), findsOneWidget);
      expect(find.text('Voice status'), findsOneWidget);
      expect(find.textContaining('PLANNED'), findsNothing);
      expect(find.text('Foundation build'), findsNothing);
      expect(find.text('Automatic detection — not supported'), findsOneWidget);
      expect(find.text('Bluetooth audio is not claimed'), findsOneWidget);
      expect(find.textContaining('continuous listening'), findsWidgets);

      final OutlinedButton scan = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Scan for Bluetooth speakers'),
      );
      expect(scan.onPressed, isNull,
          reason: 'No Bluetooth scan or simulated device is implemented.');
      expect(tester.takeException(), isNull);
    });

    testWidgets('wake and microphone switches persist and update privacy state',
        (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('Idle — no capture'), findsOneWidget);
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable wake phrase preference'),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable microphone preference'),
      );
      await tester.pumpAndSettle();

      final VoicePreferences saved = voiceStores[AuraProfile.family]!.value;
      expect(saved.wakePhraseEnabled, isTrue);
      expect(saved.microphoneEnabled, isTrue);
      expect(voiceStores[AuraProfile.family]!.saveCount, 2);
      expect(find.text('“Hey AURA” enabled'), findsOneWidget);
      expect(find.text('Requested (no detector running)'), findsOneWidget);
      expect(find.text('Idle — no capture'), findsNothing);
      expect(find.textContaining('No permission requested, no audio captured'),
          findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('language selection persists and changes the sample response',
        (WidgetTester tester) async {
      await pumpPage(tester);

      // SegmentedButton inflates its own buttons; ButtonSegment is only a
      // configuration object, so tap the rendered label instead.
      await tester.tap(find.text('हिन्दी'));
      await tester.pumpAndSettle();

      expect(
        container.read(voicePreferencesProvider).language,
        VoiceLanguage.hindi,
      );
      expect(find.textContaining('AURA तैयार है।'), findsOneWidget);
      expect(voiceStores[AuraProfile.family]!.saveCount, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('listening feedback previews all five states without audio',
        (WidgetTester tester) async {
      await pumpPage(tester);

      expect(find.text('Feedback preview: Idle'), findsOneWidget);
      await tester
          .tap(find.widgetWithText(OutlinedButton, 'Preview next state'));
      await tester.pumpAndSettle();
      expect(find.text('Feedback preview: Listening'), findsOneWidget);

      await tester.tap(find.widgetWithText(ChoiceChip, 'Success'));
      await tester.pumpAndSettle();
      expect(find.text('Feedback preview: Success'), findsOneWidget);
      expect(
        find.text('Visual states only. No transition is driven by real audio.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('volume slider persists and never claims a system audio change',
        (WidgetTester tester) async {
      await pumpPage(tester);

      await tester.drag(find.byType(Slider).first, const Offset(-90, 0));
      await tester.pumpAndSettle();

      final int volume = container.read(voicePreferencesProvider).volume;
      expect(volume, isNot(60));
      expect(voiceStores[AuraProfile.family]!.value.volume, volume);
      expect(find.textContaining('does not change Windows system volume'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('permission denied and probe failures are surfaced honestly',
        (WidgetTester tester) async {
      probe = FakeMicrophoneProbe(
        MicrophoneStatus(
          permission: MicrophonePermissionStatus.denied,
          device: MicrophoneDeviceStatus.unknown,
          captureSupported: false,
          message: 'OS permission was refused.',
        ),
      );
      await pumpPage(tester);
      expect(find.textContaining('OS permission: Denied'), findsOneWidget);
      expect(find.text('OS permission'), findsNWidgets(1));

      probe = const FailingMicrophoneProbe();
      await pumpPage(tester);
      expect(find.text('Microphone capability unavailable'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
    });

    testWidgets('reports an unsuccessful preference write',
        (WidgetTester tester) async {
      voiceStores[AuraProfile.family]!.failSaves = true;
      await pumpPage(tester);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable wake phrase preference'),
      );
      await tester.pumpAndSettle();
      expect(find.text('Could not save locally'), findsWidgets);
      expect(find.text('Saved locally'), findsNothing);
    });

    testWidgets('switching workspace swaps voice preferences',
        (WidgetTester tester) async {
      await pumpPage(tester);
      final int familySaves = voiceStores[AuraProfile.family]!.saveCount;

      container.read(profileSessionProvider.notifier).state = ProfileSession(
        profile: AuraProfile.ayush,
        startedAt: DateTime.now(),
        authenticated: true,
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('AYUSH workspace'), findsWidgets);

      await tester.tap(
        find.widgetWithText(SwitchListTile, 'Enable wake phrase preference'),
      );
      await tester.pumpAndSettle();

      expect(voiceStores[AuraProfile.family]!.saveCount, familySaves);
      expect(voiceStores[AuraProfile.ayush]!.saveCount, 1);
      expect(tester.takeException(), isNull);
    });
  });
}
