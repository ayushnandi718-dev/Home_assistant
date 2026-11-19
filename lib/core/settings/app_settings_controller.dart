import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Loads and persists [AppSettings] through a local JSON file.
///
/// `load()` is awaited in main() before the UI is created, so the app never
/// flashes default values before applying the user's preferences.
class AppSettingsController extends StateNotifier<AppSettings> {
  AppSettingsController({AppSettingsStore? store})
      : _store = store ?? AppSettingsStore(),
        super(AppSettings.defaults);

  final AppSettingsStore _store;

  Future<void> load() async {
    state = await _store.load();
  }

  Future<void> update(AppSettings next) async {
    // Keep in-memory state and the persisted file canonical so a reload never
    // changes values behind the user's back (e.g. a trailing slash in a URL).
    // `copyWith(lastActiveProfile: null)` means "unchanged", so an unsupported
    // scope must be cleared explicitly instead of relying on a null argument.
    final String? scope =
        AppSettings.normaliseProfileScope(next.lastActiveProfile);
    final AppSettings canonical = next.copyWith(
      apiBaseUrl: AppSettings.normaliseApiBaseUrl(next.apiBaseUrl),
      lastActiveProfile: scope,
      clearLastActiveProfile: scope == null,
    );
    state = canonical;
    await _store.save(canonical);
  }

  Future<void> reset() => update(AppSettings.defaults);
}
