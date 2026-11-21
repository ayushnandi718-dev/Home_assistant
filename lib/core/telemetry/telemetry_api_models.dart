import 'package:aura_hub/core/platform/io_compat.dart';

/// Lifecycle states shown by AURA Hub for its local telemetry API.
enum TelemetryApiStatus {
  starting,
  online,
  reconnecting,
  offline,
  startupFailed,
}

extension TelemetryApiStatusX on TelemetryApiStatus {
  String get label => switch (this) {
        TelemetryApiStatus.starting => 'Starting',
        TelemetryApiStatus.online => 'Online',
        TelemetryApiStatus.reconnecting => 'Reconnecting',
        TelemetryApiStatus.offline => 'Offline',
        TelemetryApiStatus.startupFailed => 'Startup failed',
      };

  bool get isTerminalFailure => this == TelemetryApiStatus.startupFailed;
}

/// Stable, non-sensitive reason codes for telemetry API failures.
enum TelemetryApiIssue {
  none,
  disabled,
  runtimeMissing,
  apiSourceMissing,
  startupTimeout,
  portOccupied,
  missingDependency,
  pythonError,
  processExited,
  connectionFailed,
  anotherInstanceStarting,
  unknown,
}

/// Immutable configuration for the app-managed telemetry API process.
class TelemetryApiConfig {
  const TelemetryApiConfig({
    this.host = '127.0.0.1',
    this.port = 8765,
    this.autoStart = true,
    this.startupTimeout = const Duration(seconds: 20),
    this.healthPollInterval = const Duration(milliseconds: 250),
    this.healthTimeout = const Duration(seconds: 2),
    this.restartBackoff = const Duration(seconds: 2),
    this.maxRestartAttempts = 3,
    this.shutdownTimeout = const Duration(seconds: 4),
    this.maxLogBytes = 512 * 1024,
    this.maxLogFiles = 3,
  });

  final String host;
  final int port;
  final bool autoStart;
  final Duration startupTimeout;
  final Duration healthPollInterval;
  final Duration healthTimeout;
  final Duration restartBackoff;
  final int maxRestartAttempts;
  final Duration shutdownTimeout;
  final int maxLogBytes;
  final int maxLogFiles;

  Uri get baseUri => Uri(scheme: 'http', host: host, port: port);

  Uri get healthUri => baseUri.replace(path: '/api/health');

  Uri get shutdownUri => baseUri.replace(path: '/api/shutdown');

  TelemetryApiConfig copyWith({
    String? host,
    int? port,
    bool? autoStart,
    Duration? startupTimeout,
    Duration? healthPollInterval,
    Duration? healthTimeout,
    Duration? restartBackoff,
    int? maxRestartAttempts,
    Duration? shutdownTimeout,
    int? maxLogBytes,
    int? maxLogFiles,
  }) {
    return TelemetryApiConfig(
      host: host ?? this.host,
      port: port ?? this.port,
      autoStart: autoStart ?? this.autoStart,
      startupTimeout: startupTimeout ?? this.startupTimeout,
      healthPollInterval: healthPollInterval ?? this.healthPollInterval,
      healthTimeout: healthTimeout ?? this.healthTimeout,
      restartBackoff: restartBackoff ?? this.restartBackoff,
      maxRestartAttempts: maxRestartAttempts ?? this.maxRestartAttempts,
      shutdownTimeout: shutdownTimeout ?? this.shutdownTimeout,
      maxLogBytes: maxLogBytes ?? this.maxLogBytes,
      maxLogFiles: maxLogFiles ?? this.maxLogFiles,
    );
  }
}

/// Observable state for the local telemetry service. Never contains paths to
/// private data, credentials, process command lines or raw Python output.
class TelemetryApiState {
  const TelemetryApiState({
    this.status = TelemetryApiStatus.offline,
    this.issue = TelemetryApiIssue.none,
    this.message = 'Telemetry service is offline.',
    this.lastCheckedAt,
    this.restartAttempts = 0,
    this.managedProcessRunning = false,
  });

  final TelemetryApiStatus status;
  final TelemetryApiIssue issue;
  final String message;
  final DateTime? lastCheckedAt;
  final int restartAttempts;
  final bool managedProcessRunning;

  bool get isOnline => status == TelemetryApiStatus.online;

  TelemetryApiState copyWith({
    TelemetryApiStatus? status,
    TelemetryApiIssue? issue,
    String? message,
    DateTime? lastCheckedAt,
    int? restartAttempts,
    bool? managedProcessRunning,
  }) {
    return TelemetryApiState(
      status: status ?? this.status,
      issue: issue ?? this.issue,
      message: message ?? this.message,
      lastCheckedAt: lastCheckedAt ?? this.lastCheckedAt,
      restartAttempts: restartAttempts ?? this.restartAttempts,
      managedProcessRunning:
          managedProcessRunning ?? this.managedProcessRunning,
    );
  }
}

/// Result of a health probe. [portOpen] distinguishes an unrelated service on
/// the configured port from no listener at all.
class TelemetryHealthResult {
  const TelemetryHealthResult({
    required this.healthy,
    required this.portOpen,
  });

  final bool healthy;
  final bool portOpen;

  static const TelemetryHealthResult healthyResult = TelemetryHealthResult(
    healthy: true,
    portOpen: true,
  );
  static const TelemetryHealthResult unreachable = TelemetryHealthResult(
    healthy: false,
    portOpen: false,
  );
  static const TelemetryHealthResult unrelatedService = TelemetryHealthResult(
    healthy: false,
    portOpen: true,
  );
}

/// A discovered Python executable and any launcher arguments it requires.
class TelemetryRuntime {
  const TelemetryRuntime({
    required this.executable,
    this.prefixArguments = const <String>[],
    required this.source,
  });

  final String executable;
  final List<String> prefixArguments;
  final String source;

  List<String> argumentsFor(List<String> scriptArguments) =>
      <String>[...prefixArguments, ...scriptArguments];
}

/// Reason a managed process stopped, derived only from redacted output.
enum TelemetryProcessExitKind {
  portOccupied,
  missingDependency,
  pythonError,
  unknown,
}

class TelemetryProcessExitInfo {
  const TelemetryProcessExitInfo({
    required this.kind,
    required this.exitCode,
  });

  final TelemetryProcessExitKind kind;
  final int? exitCode;

  bool get isRetryable => switch (kind) {
        TelemetryProcessExitKind.portOccupied ||
        TelemetryProcessExitKind.missingDependency =>
          false,
        TelemetryProcessExitKind.pythonError ||
        TelemetryProcessExitKind.unknown =>
          true,
      };
}

/// Bundled or discovered source layout for the telemetry API.
class TelemetryApiSource {
  const TelemetryApiSource({
    required this.root,
    required this.entryPoint,
    required this.workingDirectory,
  });

  final Directory root;
  final File entryPoint;
  final Directory workingDirectory;

  bool get isValid => entryPoint.existsSync();
}
