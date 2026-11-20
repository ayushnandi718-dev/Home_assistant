import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_store.dart';
import 'package:aura_hub/features/dashboard/data/dashboard_layout_store.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/display/data/display_preferences_store.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/voice_audio/data/voice_preferences_store.dart';
import 'package:aura_hub/features/voice_audio/domain/microphone_probe.dart';
import 'package:aura_hub/features/voice_audio/domain/voice_preferences.dart';

/// Test-only stores backed by memory. They keep Phase 3 widget tests away from
/// the real AURA app-data directory while exercising the real controllers.
class MemoryDisplayStore extends DisplayPreferencesStore {
  MemoryDisplayStore(Directory directory, AuraProfile profile)
      : super(directory: directory, profile: profile);

  DisplayPreferences value = DisplayPreferences.defaults;
  int saveCount = 0;
  bool failSaves = false;

  @override
  Future<DisplayPreferences> load() async => value;

  @override
  Future<bool> save(DisplayPreferences preferences) async {
    if (failSaves) return false;
    value = preferences;
    saveCount++;
    return true;
  }
}

class MemoryVoiceStore extends VoicePreferencesStore {
  MemoryVoiceStore(Directory directory, AuraProfile profile)
      : super(directory: directory, profile: profile);

  VoicePreferences value = VoicePreferences.defaults;
  VoicePreferencesLoadResult? loadResult;
  int saveCount = 0;
  bool failSaves = false;

  @override
  Future<VoicePreferencesLoadResult> loadWithStatus() async =>
      loadResult ?? VoicePreferencesLoadResult(preferences: value);

  @override
  Future<VoicePreferences> load() async => (await loadWithStatus()).preferences;

  @override
  Future<bool> save(VoicePreferences preferences) async {
    if (failSaves) return false;
    value = preferences;
    saveCount++;
    return true;
  }
}

class MemoryLayoutStore extends DashboardLayoutStore {
  MemoryLayoutStore(Directory directory, AuraProfile profile)
      : super(directory: directory, profile: profile);

  DashboardLayout value = DashboardLayout.defaults;
  int saveCount = 0;
  bool failSaves = false;

  @override
  Future<DashboardLayout> load() async => value;

  @override
  Future<bool> save(DashboardLayout layout) async {
    if (failSaves) return false;
    value = layout;
    saveCount++;
    return true;
  }
}

class MemoryAppSettingsStore extends AppSettingsStore {
  MemoryAppSettingsStore(Directory directory) : super(directory: directory);

  AppSettings value = AppSettings.defaults;

  @override
  Future<AppSettings> load() async => value;

  @override
  Future<void> save(AppSettings settings) async {
    value = settings;
  }
}

class FakeMicrophoneProbe extends MicrophoneProbe {
  const FakeMicrophoneProbe(this.status);

  final MicrophoneStatus status;

  @override
  Future<MicrophoneStatus> probe() async => status;
}

class FailingMicrophoneProbe extends MicrophoneProbe {
  const FailingMicrophoneProbe();

  @override
  Future<MicrophoneStatus> probe() =>
      Future<MicrophoneStatus>.error(StateError('probe unavailable'));
}
