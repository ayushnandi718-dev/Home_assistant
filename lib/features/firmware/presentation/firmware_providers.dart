import 'dart:async';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/features/firmware/data/firmware_update_preferences_store.dart';
import 'package:aura_hub/features/firmware/domain/firmware_update_preferences.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Honest feedback for the Firmware Update footer.
enum FirmwareSaveState { saved, saving, failed }

extension FirmwareSaveStateX on FirmwareSaveState {
  String get label => switch (this) {
        FirmwareSaveState.saved => 'Saved locally',
        FirmwareSaveState.saving => 'Saving…',
        FirmwareSaveState.failed => 'Could not save locally',
      };
}

/// Reads bytes for the local digest tool. Injectable so widget tests never
/// depend on real filesystem I/O.
typedef FirmwareFileReader = Future<List<int>> Function(String path);

/// Real file reader used by the app. It only reads a path the user typed; it
/// never downloads or transmits anything.
final Provider<FirmwareFileReader> firmwareFileReaderProvider =
    Provider<FirmwareFileReader>((Ref ref) {
  return (String path) => File(path).readAsBytes();
});

/// Owns one workspace's firmware preferences and persists every edit immediately.
///
/// It stores configuration only. There is no download, install, verification or
/// device command method on this controller by design.
class FirmwareUpdatePreferencesController
    extends StateNotifier<FirmwareUpdatePreferences> {
  FirmwareUpdatePreferencesController({FirmwareUpdatePreferencesStore? store})
      : _store = store ??
            FirmwareUpdatePreferencesStore(profile: AuraProfile.family),
        super(FirmwareUpdatePreferences.defaults);

  final FirmwareUpdatePreferencesStore _store;
  final ValueNotifier<FirmwareSaveState> saveState =
      ValueNotifier<FirmwareSaveState>(FirmwareSaveState.saved);

  int _saveRevision = 0;

  Future<void> load() async => state = await _store.load();

  void update(FirmwareUpdatePreferences next) {
    if (next == state) return;
    state = next;
    unawaited(_persist());
  }

  Future<void> reset() async {
    state = FirmwareUpdatePreferences.defaults;
    await _persist();
  }

  Future<void> _persist() async {
    final int revision = ++_saveRevision;
    saveState.value = FirmwareSaveState.saving;
    final bool ok = await _store.save(state);
    if (revision != _saveRevision) return;
    saveState.value = ok ? FirmwareSaveState.saved : FirmwareSaveState.failed;
  }

  @override
  void dispose() {
    saveState.dispose();
    super.dispose();
  }
}

/// One independent, persisted configuration per workspace.
final StateNotifierProviderFamily<FirmwareUpdatePreferencesController,
        FirmwareUpdatePreferences, AuraProfile>
    firmwareUpdatePreferencesForProvider = StateNotifierProvider.family<
        FirmwareUpdatePreferencesController,
        FirmwareUpdatePreferences,
        AuraProfile>((Ref ref, AuraProfile profile) {
  return FirmwareUpdatePreferencesController(
    store: FirmwareUpdatePreferencesStore(profile: profile),
  );
});

/// Plain provider on purpose: the controller is owned and disposed by the
/// family above, so switching workspaces swaps data sources without a second
/// dispose. Both controllers are preloaded in `main()`.
final Provider<FirmwareUpdatePreferences> firmwareUpdatePreferencesProvider =
    Provider<FirmwareUpdatePreferences>((Ref ref) {
  return ref.watch(
    firmwareUpdatePreferencesForProvider(ref.watch(activeProfileProvider)),
  );
});

/// Commands for the active workspace's firmware preferences.
final Provider<FirmwareUpdatePreferencesController>
    activeFirmwareUpdatePreferencesControllerProvider =
    Provider<FirmwareUpdatePreferencesController>((Ref ref) {
  return ref.watch(
    firmwareUpdatePreferencesForProvider(ref.watch(activeProfileProvider))
        .notifier,
  );
});
