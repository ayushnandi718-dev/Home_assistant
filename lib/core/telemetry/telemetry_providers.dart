import 'dart:async';
import 'package:aura_hub/core/platform/io_compat.dart';

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

/// One cryptographically random token per app launch, held only in memory.
///
/// Both the child process environment and the dashboard API client read this
/// same provider. It is never written to settings, diagnostics or process
/// arguments.
final Provider<String> telemetryApiAuthTokenProvider =
    Provider<String>((Ref ref) => generateTelemetryApiAuthToken());

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
/// dashboard navigation and is stopped only on app shutdown. It *is* rebuilt
/// when the persisted enable flag or endpoint changes, which cleanly shuts down
/// the previous AURA-owned process through `ref.onDispose` before constructing
/// a replacement. No cloud telemetry is introduced by this control.
final StateNotifierProvider<TelemetryApiService, TelemetryApiState>
    telemetryApiServiceProvider =
    StateNotifierProvider<TelemetryApiService, TelemetryApiState>((Ref ref) {
  // Watch only the fields that affect the service so unrelated preference
  // changes (theme, density, ...) do not restart the sampler.
  final bool telemetryEnabled = ref.watch(
    appSettingsProvider.select((AppSettings s) => s.telemetryEnabled),
  );
  final String apiBaseUrl = ref.watch(
    appSettingsProvider.select((AppSettings s) => s.apiBaseUrl),
  );
  final Uri? endpoint = Uri.tryParse(apiBaseUrl);
  final String host =
      endpoint?.host.isNotEmpty == true ? endpoint!.host : '127.0.0.1';
  final int parsedPort = endpoint?.port ?? 0;
  final int port = parsedPort == 0 ? 8765 : parsedPort;
  final String autoStartValue =
      Platform.environment['AURA_TELEMETRY_AUTOSTART']?.toLowerCase() ?? '';
  final bool loopback = AppSettings.isLoopbackApiHost(host);
  final bool autoStart = loopback &&
      telemetryEnabled &&
      autoStartValue != 'false' &&
      autoStartValue != '0';

  // Surface a stored legacy insecure URL as a visible failure. Never rewrite
  // the host, scheme or port behind the user's back.
  final bool insecureHttp = endpoint?.scheme.toLowerCase() == 'http' &&
      !AppSettings.isLoopbackApiHost(endpoint!.host);
  final String? endpointError = AppSettings.validateApiBaseUrl(apiBaseUrl);
  final TelemetryApiIssue startupIssue = endpointError == null
      ? TelemetryApiIssue.none
      : (insecureHttp
          ? TelemetryApiIssue.insecureEndpoint
          : TelemetryApiIssue.invalidEndpoint);

  final TelemetryApiConfig config = TelemetryApiConfig(
    host: host,
    port: port,
    autoStart: autoStart,
    authToken: ref.read(telemetryApiAuthTokenProvider),
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
    enabled: telemetryEnabled,
    startupIssue: startupIssue,
    startupMessage: endpointError,
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
