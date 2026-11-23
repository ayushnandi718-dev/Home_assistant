import 'package:aura_hub/features/memory/presentation/memory_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/security/data/ayush_security_settings_store.dart';
import 'package:aura_hub/features/security/domain/ayush_security_settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Private-access reader for AYUSH security settings.
typedef SecurityAccessReader = ProfileAccess Function();

/// Immutable view of private security settings plus any storage problem.
///
/// A storage failure never silently becomes an insecure value: the UI keeps
/// the safe 5-minute default and shows an explicit error instead.
class AyushSecuritySettingsState {
  const AyushSecuritySettingsState({
    this.settings = AyushSecuritySettings.defaults,
    this.error,
    this.loaded = false,
  });

  final AyushSecuritySettings settings;
  final String? error;
  final bool loaded;

  AyushSecuritySettingsState copyWith({
    AyushSecuritySettings? settings,
    String? error,
    bool? loaded,
    bool clearError = false,
  }) =>
      AyushSecuritySettingsState(
        settings: settings ?? this.settings,
        error: clearError ? null : error ?? this.error,
        loaded: loaded ?? this.loaded,
      );
}

/// Loads and saves AYUSH-only security preferences through the encrypted store.
///
/// Both reads and writes require an authenticated private session; the guard is
/// in the controller, not merely in the UI.
class AyushSecuritySettingsController
    extends StateNotifier<AyushSecuritySettingsState> {
  AyushSecuritySettingsController({
    required AyushSecuritySettingsStorage store,
    required SecurityAccessReader accessReader,
  })  : _store = store,
        _accessReader = accessReader,
        super(const AyushSecuritySettingsState());

  final AyushSecuritySettingsStorage _store;
  final SecurityAccessReader _accessReader;

  Future<void> load({bool force = false}) async {
    _requirePrivate();
    if (state.loaded && !force) return;
    try {
      final AyushSecuritySettings settings = await _store.load();
      state = AyushSecuritySettingsState(settings: settings, loaded: true);
    } catch (_) {
      state = AyushSecuritySettingsState(
        settings: AyushSecuritySettings.defaults,
        error: 'Private security settings could not be read. '
            'The safe 5-minute lock is in effect.',
        loaded: true,
      );
    }
  }

  Future<void> update(AyushAutoLock autoLock) async {
    await _save(state.settings.copyWith(autoLock: autoLock));
  }

  /// Updates the background grace without ever allowing it to be disabled.
  Future<void> updateBackgroundLockGrace(
    AyushBackgroundLockGrace grace,
  ) async {
    await _save(state.settings.copyWith(backgroundLockGrace: grace));
  }

  Future<void> _save(AyushSecuritySettings next) async {
    _requirePrivate();
    try {
      await _store.save(next);
      state = state.copyWith(settings: next, clearError: true);
    } catch (_) {
      state = state.copyWith(
        error: 'Could not save the private lock setting. '
            'The previous value remains in effect.',
      );
    }
  }

  /// Drops decrypted private settings from memory when AYUSH locks. Allowed
  /// without the private guard because it only removes data.
  void clear() {
    state = const AyushSecuritySettingsState();
  }

  void _requirePrivate() {
    final ProfileAccess access = _accessReader();
    access.requirePrivate<bool>(AuraProfile.ayush, true);
  }
}

final Provider<AyushSecuritySettingsStorage>
    ayushSecuritySettingsStoreProvider =
    Provider<AyushSecuritySettingsStorage>((Ref ref) {
  return EncryptedAyushSecuritySettingsStore(
    cipher: ref.read(ayushMemoryCipherProvider),
  );
});

/// Guarded controller for AYUSH-only security preferences.
///
/// It is intentionally kept alive (not auto-disposed) so the auto-lock monitor
/// can observe it, but reads/writes still require an authenticated private
/// session and [AyushSecuritySettingsController.clear] wipes the decrypted
/// values from memory on lock.
final StateNotifierProvider<AyushSecuritySettingsController,
        AyushSecuritySettingsState> ayushSecuritySettingsProvider =
    StateNotifierProvider<AyushSecuritySettingsController,
        AyushSecuritySettingsState>((Ref ref) {
  return AyushSecuritySettingsController(
    store: ref.read(ayushSecuritySettingsStoreProvider),
    accessReader: () => ref.read(profileAccessProvider),
  );
});
