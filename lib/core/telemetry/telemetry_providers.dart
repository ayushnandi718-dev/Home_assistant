import 'dart:async';
import 'dart:io';

import 'package:aura_hub/core/config/aura_runtime_config.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_probe.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_service.dart';
import 'package:aura_hub/core/telemetry/telemetry_log_store.dart';
import 'package:aura_hub/core/telemetry/telemetry_process.dart';
import 'package:aura_hub/core/telemetry/telemetry_runtime_locator.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<TelemetryApiLogStore> telemetryApiLogStoreProvider =
    Provider<TelemetryApiLogStore>((Ref ref) {
  final Directory logs = Directory(
    '${LocalPaths.appData().path}${Platform.pathSeparator}logs',
  );
  return TelemetryApiLogStore(directory: logs);
});

/// App-wide state for the hidden local telemetry service.
///
/// The provider is intentionally not auto-dispose: the service must survive
/// dashboard navigation and is stopped only on app shutdown.
final StateNotifierProvider<TelemetryApiService, TelemetryApiState>
    telemetryApiServiceProvider =
    StateNotifierProvider<TelemetryApiService, TelemetryApiState>((Ref ref) {
  final AppSettings settings = ref.read(appSettingsProvider);
  final Uri? endpoint = Uri.tryParse(settings.apiBaseUrl);
  final String host =
      endpoint?.host.isNotEmpty == true ? endpoint!.host : '127.0.0.1';
  final int port = endpoint?.port ?? 8765;
  final String autoStartValue =
      Platform.environment['AURA_TELEMETRY_AUTOSTART']?.toLowerCase() ?? '';
  final bool autoStart = settings.isLoopbackApi &&
      autoStartValue != 'false' &&
      autoStartValue != '0';

  final TelemetryApiConfig config = TelemetryApiConfig(
    host: host,
    port: port,
    autoStart: autoStart,
  );
  final DartTelemetryApiProbe probe = DartTelemetryApiProbe(config: config);
  final TelemetryApiService service = TelemetryApiService(
    config: config,
    probe: probe,
    launcher: const DartTelemetryProcessLauncher(),
    runtimeLocator: const TelemetryRuntimeLocator(),
    sourceLocator: const TelemetryApiSourceLocator(),
    logStore: ref.read(telemetryApiLogStoreProvider),
    lockDirectory: LocalPaths.appData(),
  );

  ref.onDispose(() {
    unawaited(service.shutdown());
    probe.close();
  });
  // Defer out of provider construction: Riverpod forbids state mutation while
  // a provider is still building. main() reads this provider once to arm it.
  scheduleMicrotask(() {
    if (AuraRuntimeConfig.backgroundServicesEnabled && autoStart) {
      unawaited(service.start());
    }
  });
  return service;
});

/// Read-only view used by the dashboard/settings status cards.
final Provider<TelemetryApiState> telemetryApiStateProvider =
    Provider<TelemetryApiState>((Ref ref) {
  return ref.watch(telemetryApiServiceProvider);
});
