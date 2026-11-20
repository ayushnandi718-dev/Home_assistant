import 'dart:async';

import 'package:aura_hub/features/display/data/display_preferences_store.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest feedback for the Display Studio footer.
enum DisplaySaveState { saved, saving, failed }

extension DisplaySaveStateX on DisplaySaveState {
  String get label => switch (this) {
        DisplaySaveState.saved => 'Saved locally',
        DisplaySaveState.saving => 'Saving…',
        DisplaySaveState.failed => 'Could not save locally',
      };
}

/// Owns one workspace's display preferences and persists every edit immediately.
class DisplayPreferencesController extends StateNotifier<DisplayPreferences> {
  DisplayPreferencesController({DisplayPreferencesStore? store})
      : _store = store ?? DisplayPreferencesStore(profile: AuraProfile.family),
        super(DisplayPreferences.defaults);

  final DisplayPreferencesStore _store;
  final ValueNotifier<DisplaySaveState> saveState =
      ValueNotifier<DisplaySaveState>(DisplaySaveState.saved);

  int _saveRevision = 0;

  Future<void> load() async => state = await _store.load();

  void update(DisplayPreferences next) {
    if (next == state) return;
    state = next;
    unawaited(_persist());
  }

  Future<void> reset() async {
    state = DisplayPreferences.defaults;
    await _persist();
  }

  Future<void> _persist() async {
    final int revision = ++_saveRevision;
    saveState.value = DisplaySaveState.saving;
    final bool ok = await _store.save(state);
    if (revision != _saveRevision) return;
    saveState.value = ok ? DisplaySaveState.saved : DisplaySaveState.failed;
  }

  @override
  void dispose() {
    saveState.dispose();
    super.dispose();
  }
}

/// One independent, persisted configuration per workspace.
final StateNotifierProviderFamily<DisplayPreferencesController,
        DisplayPreferences, AuraProfile> displayPreferencesForProvider =
    StateNotifierProvider.family<DisplayPreferencesController,
        DisplayPreferences, AuraProfile>((Ref ref, AuraProfile profile) {
  return DisplayPreferencesController(
    store: DisplayPreferencesStore(profile: profile),
  );
});

/// Plain provider on purpose: the controller is owned and disposed by the
/// family above, so switching workspaces swaps data sources without a second
/// dispose. Both controllers are preloaded in `main()`.
final Provider<DisplayPreferences> displayPreferencesProvider =
    Provider<DisplayPreferences>((Ref ref) {
  return ref
      .watch(displayPreferencesForProvider(ref.watch(activeProfileProvider)));
});

/// Commands for the active workspace's display preferences.
final Provider<DisplayPreferencesController>
    activeDisplayPreferencesControllerProvider =
    Provider<DisplayPreferencesController>((Ref ref) {
  return ref.watch(
    displayPreferencesForProvider(ref.watch(activeProfileProvider)).notifier,
  );
});
