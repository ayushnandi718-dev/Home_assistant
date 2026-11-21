import 'dart:async';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/error/app_error_handler.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:aura_hub/features/firmware/presentation/firmware_providers.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/voice_audio/presentation/voice_providers.dart';
import 'package:aura_hub/features/security/presentation/auto_lock_controller.dart';
import 'package:aura_hub/features/startup/presentation/startup_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  ProviderContainer? container;

  // The binding and runApp must share a zone. Initializing the binding before
  // entering the guarded zone trips Flutter's debug zone-mismatch assertion and
  // prevents the Web preview from rendering.
  await runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();

      // Android must resolve its app-private data directory before Riverpod
      // creates any local store. Without this, PIN and workspace persistence
      // fall back to the process working directory and writes fail.
      await LocalPaths.initialize();

      // Load persisted preferences and both notification histories before the
      // first frame so settings and unread counts are correct from the start.
      final ProviderContainer activeContainer = ProviderContainer();
      container = activeContainer;
      await activeContainer.read(appSettingsProvider.notifier).load();
      // Reconcile the persisted startup preference with the single CurrentUser
      // Run entry before the first frame. This makes the toggle reversible and
      // removes a stale entry if the app was uninstalled/reinstalled or settings
      // were edited.
      await activeContainer
          .read(startupControllerProvider.notifier)
          .apply(activeContainer.read(appSettingsProvider));
      for (final AuraProfile profile in AuraProfile.values) {
        // Both workspaces keep an independent dashboard layout; load them
        // before the first frame so switching profiles never flashes defaults.
        await activeContainer
            .read(dashboardLayoutForProvider(profile).notifier)
            .load();
        // Display Studio and Voice & Audio keep independent, profile-scoped
        // preferences. Load them before the first frame so switching workspaces
        // never flashes another profile's configuration.
        await activeContainer
            .read(displayPreferencesForProvider(profile).notifier)
            .load();
        await activeContainer
            .read(voicePreferencesForProvider(profile).notifier)
            .load();
        await activeContainer
            .read(firmwareUpdatePreferencesForProvider(profile).notifier)
            .load();
        await activeContainer
            .read(notificationCenterForProvider(profile).notifier)
            .load();
      }

      installGlobalErrorHandling(activeContainer);
      AuraRuntimeConfig.backgroundServicesEnabled = true;

      // The Windows runner invokes this just before engine teardown so the
      // hidden telemetry API can be stopped and logged synchronously. The
      // native Job Object remains the final cleanup guarantee if this hook is
      // missed.
      if (Platform.isWindows) {
        const MethodChannel lifecycleChannel =
            MethodChannel('aura_hub/lifecycle');
        lifecycleChannel.setMethodCallHandler((MethodCall call) async {
          if (call.method == 'shutdown') {
            await activeContainer
                .read(telemetryApiServiceProvider.notifier)
                .shutdown();
          }
          return null;
        });
      }

      runApp(
        UncontrolledProviderScope(
          container: activeContainer,
          child: const AuraApp(),
        ),
      );
      // AuraApp owns the in-process service lifecycle (start/pause/resume/stop).
      // The telemetry service provider starts the hidden Python API once; its
      // Windows job handle also guarantees cleanup if the app exits abruptly.
      activeContainer.read(telemetryApiServiceProvider.notifier);
      // Instantiate the single AYUSH inactivity monitor for the app lifetime.
      // It only arms while a private session is active, so startup stays in
      // FAMILY and never auto-unlocks AYUSH.
      activeContainer.read(ayushAutoLockControllerProvider);
      // Track the active profile scope only when the user opted in.
      activeContainer.read(rememberedProfileTrackerProvider);
    },
    (Object error, StackTrace stack) {
      final ProviderContainer? activeContainer = container;
      if (activeContainer != null) {
        recordZoneError(activeContainer, error, stack);
      }
    },
  );
}
