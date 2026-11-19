import 'dart:io';

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/startup/data/startup_service.dart';
import 'package:aura_hub/features/startup/data/windows_startup_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Windows gets the real CurrentUser Run-key service; every other platform and
/// test environment gets an explicit no-op with a user-facing explanation.
final Provider<StartupService> startupServiceProvider =
    Provider<StartupService>((Ref ref) {
  if (Platform.isWindows) return WindowsStartupService();
  return const UnsupportedStartupService();
});

class StartupState {
  const StartupState({this.applying = false, this.result});

  final bool applying;
  final StartupApplyResult? result;
}

/// Applies the persisted startup preference to the operating system and keeps
/// the last outcome so the settings UI can explain failures honestly.
class StartupController extends StateNotifier<StartupState> {
  StartupController({required StartupService service})
      : _service = service,
        super(const StartupState());

  final StartupService _service;

  bool get supported => _service.supported;

  Future<void> apply(AppSettings settings) async {
    if (!_service.supported) {
      state = StartupState(
        result: const StartupApplyResult(
          ok: false,
          error: 'Windows startup integration is unavailable on this device.',
        ),
      );
      return;
    }
    state = const StartupState(applying: true);
    final StartupApplyResult result = await _service.apply(
      enabled: settings.launchAtStartup,
      startMinimized: settings.startMinimized,
    );
    state = StartupState(result: result);
  }
}

final StateNotifierProvider<StartupController, StartupState>
    startupControllerProvider =
    StateNotifierProvider<StartupController, StartupState>(
  (Ref ref) => StartupController(service: ref.read(startupServiceProvider)),
);

/// Whether a restart should offer the AYUSH PIN prompt.
///
/// This is only a prompt decision: the remembered scope never restores an
/// authenticated session. Kept as a provider so the security rule is testable
/// without rendering the whole app shell.
final Provider<bool> shouldPromptAyushUnlockProvider =
    Provider<bool>((Ref ref) {
  final AppSettings settings = ref.watch(appSettingsProvider);
  return settings.rememberLastProfile &&
      settings.lastActiveProfile == AuraProfile.ayush.storageScope;
});

/// Records the active profile scope only while "remember last profile" is on.
///
/// It stores a scope name, never any PIN or authentication state. The remembered
/// AYUSH scope is used only to show the PIN prompt on the next launch; it can
/// never unlock the private workspace by itself.
final Provider<Object> rememberedProfileTrackerProvider =
    Provider<Object>((Ref ref) {
  ref.listen<ProfileSession>(profileSessionProvider, (_, ProfileSession next) {
    final AppSettings settings = ref.read(appSettingsProvider);
    if (!settings.rememberLastProfile) return;
    final String scope = next.profile.storageScope;
    if (settings.lastActiveProfile != scope) {
      ref
          .read(appSettingsProvider.notifier)
          .update(settings.copyWith(lastActiveProfile: scope));
    }
  });
  return const Object();
});
