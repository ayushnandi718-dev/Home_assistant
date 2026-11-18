import 'dart:async';

import 'package:aura_hub/app/aura_app.dart';
import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/error/app_error_handler.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/notifications/presentation/notification_providers.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter/material.dart';
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

  runZonedGuarded<void>(
    () {
      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const AuraApp(),
        ),
      );
      // AuraApp owns the in-process service lifecycle (start/pause/resume/stop).
      // The local Python API remains a manual, user-controlled process.
    },
    (Object error, StackTrace stack) =>
        recordZoneError(container, error, stack),
  );
}
