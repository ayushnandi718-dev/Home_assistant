import 'dart:async';

import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/voice_audio/data/voice_preferences_store.dart';
import 'package:aura_hub/features/voice_audio/domain/microphone_probe.dart';
import 'package:aura_hub/features/voice_audio/domain/voice_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest feedback for the Voice & Audio footer.
enum VoiceSaveState { saved, saving, failed }

extension VoiceSaveStateX on VoiceSaveState {
  String get label => switch (this) {
        VoiceSaveState.saved => 'Saved locally',
        VoiceSaveState.saving => 'Saving…',
        VoiceSaveState.failed => 'Could not save locally',
      };
}

/// Owns one workspace's voice preferences and persists every edit immediately.
class VoicePreferencesController extends StateNotifier<VoicePreferences> {
  VoicePreferencesController({VoicePreferencesStore? store})
      : _store = store ?? VoicePreferencesStore(profile: AuraProfile.family),
        super(VoicePreferences.defaults);

  final VoicePreferencesStore _store;
  final ValueNotifier<VoiceSaveState> saveState =
      ValueNotifier<VoiceSaveState>(VoiceSaveState.saved);

  int _saveRevision = 0;
  bool _writeProtected = false;

  Future<void> load() async {
    final VoicePreferencesLoadResult result = await _store.loadWithStatus();
    state = result.preferences;
    _writeProtected = result.writeProtected;
    if (result.writeProtected) {
      // Controlled schema error (e.g. unsupported future version): preserve the
      // original file and report an honest non-saved state.
      saveState.value = VoiceSaveState.failed;
    }
  }

  void update(VoicePreferences next) {
    if (_writeProtected) return;
    if (next == state) return;
    state = next;
    unawaited(_persist());
  }

  Future<void> reset() async {
    if (_writeProtected) return;
    state = VoicePreferences.defaults;
    await _persist();
  }

  Future<void> _persist() async {
    if (_writeProtected) return;
    final int revision = ++_saveRevision;
    saveState.value = VoiceSaveState.saving;
    final bool ok = await _store.save(state);
    if (revision != _saveRevision) return;
    saveState.value = ok ? VoiceSaveState.saved : VoiceSaveState.failed;
  }

  @override
  void dispose() {
    saveState.dispose();
    super.dispose();
  }
}

/// One independent, persisted configuration per workspace.
final StateNotifierProviderFamily<VoicePreferencesController, VoicePreferences,
        AuraProfile> voicePreferencesForProvider =
    StateNotifierProvider.family<VoicePreferencesController, VoicePreferences,
        AuraProfile>((Ref ref, AuraProfile profile) {
  return VoicePreferencesController(
    store: VoicePreferencesStore(profile: profile),
  );
});

/// Read-only microphone capability probe. Overridable in tests.
final Provider<MicrophoneProbe> microphoneProbeProvider =
    Provider<MicrophoneProbe>((Ref ref) => const DesktopMicrophoneProbe());

/// Snapshot of what this build can honestly say about microphone access.
final FutureProvider<MicrophoneStatus> microphoneStatusProvider =
    FutureProvider<MicrophoneStatus>((Ref ref) {
  return ref.watch(microphoneProbeProvider).probe();
}, dependencies: <ProviderOrFamily>[microphoneProbeProvider]);

/// Plain provider on purpose: the controller is owned and disposed by the
/// family above. Both controllers are preloaded in `main()`.
final Provider<VoicePreferences> voicePreferencesProvider =
    Provider<VoicePreferences>((Ref ref) {
  return ref
      .watch(voicePreferencesForProvider(ref.watch(activeProfileProvider)));
});

/// Commands for the active workspace's voice preferences.
final Provider<VoicePreferencesController>
    activeVoicePreferencesControllerProvider =
    Provider<VoicePreferencesController>((Ref ref) {
  return ref.watch(
    voicePreferencesForProvider(ref.watch(activeProfileProvider)).notifier,
  );
});
