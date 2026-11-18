import 'dart:async';
import 'dart:io';

import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/error/app_error_handler.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Load persisted preferences and both notification histories before the first
  // frame so settings and unread counts are correct from the start.
  final ProviderContainer container = ProviderContainer();
  await container.read(appSettingsProvider.notifier).load();
  for (final AuraProfile profile in AuraProfile.values) {
    // Both workspaces keep an independent dashboard layout; load them before
    // the first frame so switching profiles never flashes the defaults.
    await container.read(dashboardLayoutForProvider(profile).notifier).load();
    await container
        .read(notificationCenterForProvider(profile).notifier)
        .load();
  }

  installGlobalErrorHandling(container);
  AuraRuntimeConfig.backgroundServicesEnabled = true;

  // The Windows runner invokes this just before engine teardown so the hidden
  // telemetry API can be stopped and logged synchronously. The native Job
  // Object remains the final cleanup guarantee if this hook is missed.
  if (Platform.isWindows) {
    const MethodChannel lifecycleChannel = MethodChannel('aura_hub/lifecycle');
    lifecycleChannel.setMethodCallHandler((MethodCall call) async {
      if (call.method == 'shutdown') {
        await container.read(telemetryApiServiceProvider.notifier).shutdown();
      }
      return null;
    });
  }

  runZonedGuarded<void>(
    () {
      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const AuraApp(),
        ),
      );
      // AuraApp owns the in-process service lifecycle (start/pause/resume/stop).
      // The telemetry service provider starts the hidden Python API once; its
      // Windows job handle also guarantees cleanup if the app exits abruptly.
      container.read(telemetryApiServiceProvider.notifier);
    },
    (Object error, StackTrace stack) =>
        recordZoneError(container, error, stack),
  );
}
