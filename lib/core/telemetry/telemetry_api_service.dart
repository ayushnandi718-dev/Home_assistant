import 'dart:async';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_probe.dart';
import 'package:aura_hub/core/telemetry/telemetry_log_store.dart';
import 'package:aura_hub/core/telemetry/telemetry_process.dart';
import 'package:aura_hub/core/telemetry/telemetry_runtime_locator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Owns the local Python telemetry API as an app-managed background process.
///
/// The service never fakes telemetry and never changes endpoint contracts. It
/// reuses an already compatible API when present; otherwise it starts one
/// hidden process, tracks that exact process, and shuts only that process down.
class TelemetryApiService extends StateNotifier<TelemetryApiState> {
  TelemetryApiService({
    required this.config,
    required this.probe,
    required this.launcher,
    required this.runtimeLocator,
    required this.sourceLocator,
    required this.logStore,
    required this.lockDirectory,
    this.enabled = true,
  }) : super(
          enabled
              ? const TelemetryApiState()
              : const TelemetryApiState(
                  status: TelemetryApiStatus.offline,
                  issue: TelemetryApiIssue.disabled,
                  message: 'Local telemetry is turned off.',
                ),
        );

  final TelemetryApiConfig config;
  final TelemetryApiProbe probe;
  final TelemetryProcessLauncher launcher;
  final TelemetryRuntimeLocator runtimeLocator;
  final TelemetryApiSourceLocator sourceLocator;
  final TelemetryApiLogStore logStore;
  final Directory lockDirectory;

  /// User preference captured when the provider was created. Changing it
  /// invalidates the provider so the old service is shut down cleanly.
  final bool enabled;

  TelemetryManagedProcess? _process;
  StreamSubscription<String>? _outputSubscription;
  File? _lockFile;
  String? _lockToken;
  int _generation = 0;
  int _restartAttempts = 0;
  bool _started = false;
  bool _shuttingDown = false;
  TelemetryProcessExitKind _exitHint = TelemetryProcessExitKind.unknown;

  Future<void> start({bool force = false}) async {
    if (!enabled) {
      _set(
        TelemetryApiStatus.offline,
        TelemetryApiIssue.disabled,
        'Local telemetry is turned off.',
        managedProcessRunning: false,
      );
      return;
    }
    if (_shuttingDown) return;
    if (_started && !force) return;
    _started = true;
    _restartAttempts = 0;
    await _log('startup requested');

    if (!config.autoStart) {
      _set(
        TelemetryApiStatus.offline,
        TelemetryApiIssue.disabled,
        'Automatic telemetry service startup is disabled.',
      );
      return;
    }

    _set(
      TelemetryApiStatus.starting,
      TelemetryApiIssue.none,
      'Starting telemetry service…',
    );

    final TelemetryHealthResult initial = await probe.check();
    if (initial.healthy) {
      await _adoptExisting();
      return;
    }
    if (initial.portOpen) {
      await _fail(
        TelemetryApiStatus.startupFailed,
        TelemetryApiIssue.portOccupied,
        'Port ${config.port} is in use by another service. '
        'AURA Hub did not stop it.',
      );
      return;
    }

    final bool lockAcquired = await _acquireLock();
    if (!lockAcquired) {
      await _log('startup deferred',
          detail: 'another AURA instance is starting');
      final bool becameHealthy = await _waitForHealth(
        deadline: DateTime.now().add(config.startupTimeout),
      );
      if (becameHealthy) {
        await _adoptExisting();
      } else {
        await _fail(
          TelemetryApiStatus.startupFailed,
          TelemetryApiIssue.anotherInstanceStarting,
          'Another AURA instance is starting the telemetry service. '
          'Try again shortly.',
        );
      }
      return;
    }

    final TelemetryRuntime? runtime = await runtimeLocator.locate();
    if (runtime == null) {
      await _releaseLock();
      await _fail(
        TelemetryApiStatus.startupFailed,
        TelemetryApiIssue.runtimeMissing,
        'Python 3 was not found. Install Python or use a bundled runtime.',
      );
      return;
    }

    final TelemetryApiSource? source = sourceLocator.locate();
    if (source == null || !source.isValid) {
      await _releaseLock();
      await _fail(
        TelemetryApiStatus.startupFailed,
        TelemetryApiIssue.apiSourceMissing,
        'Telemetry API files are missing from this installation.',
      );
      return;
    }

    await _launch(source: source, runtime: runtime);
  }

  /// Explicit user action from AURA Hub. Resets backoff counters.
  Future<void> restart() async {
    await shutdown();
    _shuttingDown = false;
    _started = false;
    await start(force: true);
  }

  /// User-facing disable path. Stops only AURA-owned sampling and leaves the
  /// service state explicitly "off" instead of looking like a transient error.
  Future<void> disable() async {
    await shutdown();
    _shuttingDown = false;
    _started = false;
    _set(
      TelemetryApiStatus.offline,
      TelemetryApiIssue.disabled,
      'Local telemetry is turned off. No system metrics are being collected.',
      managedProcessRunning: false,
    );
  }

  /// Best-effort graceful shutdown. Safe to call more than once.
  Future<void> shutdown() async {
    if (_shuttingDown) return;
    _shuttingDown = true;
    _generation++;
    final TelemetryManagedProcess? process = _process;
    if (process != null) {
      // Write before the first await: on app exit this callback may be cut off
      // after the synchronous prefix, and the job handle still reaps the child.
      logStore.appendSync('shutdown requested', detail: 'pid ${process.pid}');
      final bool graceful = await probe.requestShutdown();
      if (graceful) {
        await process.waitForExit(config.shutdownTimeout);
      }
      if (!await process.waitForExit(Duration.zero)) {
        await process.terminate();
        await process.waitForExit(const Duration(seconds: 2));
      }
      await process.dispose();
      _process = null;
      logStore.appendSync('shutdown complete', detail: 'pid ${process.pid}');
    } else {
      logStore.appendSync('shutdown requested', detail: 'no managed process');
    }
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    await _releaseLock();
    _set(
      TelemetryApiStatus.offline,
      TelemetryApiIssue.none,
      'Telemetry service is offline.',
      managedProcessRunning: false,
    );
  }

  Future<void> _adoptExisting() async {
    await _releaseLock();
    _set(
      TelemetryApiStatus.online,
      TelemetryApiIssue.none,
      'Telemetry service running in the background.',
      managedProcessRunning: false,
    );
    await _log('reused healthy API', detail: 'external process');
  }

  Future<void> _launch({
    required TelemetryApiSource source,
    required TelemetryRuntime runtime,
  }) async {
    final int generation = ++_generation;
    _exitHint = TelemetryProcessExitKind.unknown;
    try {
      final TelemetryManagedProcess process = await launcher.launch(
        executable: runtime.executable,
        arguments: runtime.argumentsFor(<String>[
          '-u',
          source.entryPoint.path,
        ]),
        workingDirectory: source.workingDirectory.path,
        environment: <String, String>{
          'AURA_API_HOST': config.host,
          'AURA_API_PORT': config.port.toString(),
        },
      );
      _process = process;
      await _log(
        'process started',
        detail: '${runtime.source}; pid ${process.pid}; '
            'job=${process.jobGuardActive ? 'active' : 'inactive'}',
      );
      _outputSubscription = process.output.listen(
        (String line) => _handleOutput(line),
        onError: (Object error) => unawaited(
          _log('process output error', detail: error.runtimeType.toString()),
        ),
      );
      unawaited(_watchExit(process, generation));

      final bool healthy = await _waitForHealth(
        deadline: DateTime.now().add(config.startupTimeout),
        process: process,
      );
      if (!healthy) {
        if (generation != _generation ||
            _shuttingDown ||
            !identical(_process, process)) {
          return;
        }
        final TelemetryProcessExitKind hint = _exitHint;
        final TelemetryApiIssue issue =
            hint == TelemetryProcessExitKind.portOccupied
                ? TelemetryApiIssue.portOccupied
                : hint == TelemetryProcessExitKind.missingDependency
                    ? TelemetryApiIssue.missingDependency
                    : TelemetryApiIssue.startupTimeout;
        final String message = hint == TelemetryProcessExitKind.portOccupied
            ? 'Port ${config.port} is in use by another service. '
                'AURA Hub did not stop it.'
            : hint == TelemetryProcessExitKind.missingDependency
                ? 'Telemetry API dependencies are missing. '
                    'Install server requirements and restart.'
                : 'The telemetry service did not become healthy in time.';
        await _stopCurrentProcess(generation);
        await _fail(TelemetryApiStatus.startupFailed, issue, message);
        return;
      }

      if (generation != _generation || !identical(_process, process)) return;
      _set(
        TelemetryApiStatus.online,
        TelemetryApiIssue.none,
        'Telemetry service running in the background.',
        managedProcessRunning: true,
      );
      await _log('health verified');
    } on TelemetryProcessLaunchException catch (error) {
      await _releaseLock();
      await _fail(
        TelemetryApiStatus.startupFailed,
        TelemetryApiIssue.unknown,
        'The telemetry service could not be launched. '
        '${error.message}',
      );
    } on Object catch (error) {
      await _releaseLock();
      await _fail(
        TelemetryApiStatus.startupFailed,
        TelemetryApiIssue.unknown,
        'The telemetry service could not be launched.',
        detail: error.runtimeType.toString(),
      );
    }
  }

  Future<bool> _waitForHealth({
    required DateTime deadline,
    TelemetryManagedProcess? process,
  }) async {
    while (DateTime.now().isBefore(deadline)) {
      if (_shuttingDown) return false;
      if (process != null && await process.waitForExit(Duration.zero)) {
        return false;
      }
      final TelemetryHealthResult result = await probe.check();
      if (result.healthy) return true;
      await Future<void>.delayed(config.healthPollInterval);
    }
    return false;
  }

  Future<void> _watchExit(
    TelemetryManagedProcess process,
    int generation,
  ) async {
    final int exitCode = await process.exitCode;
    if (generation != _generation || _shuttingDown) return;
    if (!identical(_process, process)) return;

    await _log('unexpected exit', detail: 'code $exitCode');
    await _releaseLock();
    _process = null;
    final TelemetryProcessExitInfo info = TelemetryProcessExitInfo(
      kind: _exitHint,
      exitCode: exitCode,
    );
    if (!info.isRetryable) {
      final TelemetryApiIssue issue =
          info.kind == TelemetryProcessExitKind.portOccupied
              ? TelemetryApiIssue.portOccupied
              : TelemetryApiIssue.missingDependency;
      await _fail(
        TelemetryApiStatus.startupFailed,
        issue,
        info.kind == TelemetryProcessExitKind.portOccupied
            ? 'Port ${config.port} is in use by another service.'
            : 'Telemetry API dependencies are missing.',
      );
      return;
    }
    if (_restartAttempts >= config.maxRestartAttempts) {
      await _fail(
        TelemetryApiStatus.offline,
        TelemetryApiIssue.processExited,
        'The telemetry service stopped repeatedly. Use Restart service.',
      );
      return;
    }

    _restartAttempts++;
    _set(
      TelemetryApiStatus.reconnecting,
      TelemetryApiIssue.processExited,
      'Telemetry service stopped unexpectedly. Reconnecting…',
      managedProcessRunning: false,
    );
    await Future<void>.delayed(config.restartBackoff * _restartAttempts);
    if (_shuttingDown || generation != _generation) return;
    await _restartAfterCrash();
  }

  Future<void> _restartAfterCrash() async {
    final TelemetryRuntime? runtime = await runtimeLocator.locate();
    final TelemetryApiSource? source = sourceLocator.locate();
    if (runtime == null || source == null || !source.isValid) {
      await _fail(
        TelemetryApiStatus.startupFailed,
        runtime == null
            ? TelemetryApiIssue.runtimeMissing
            : TelemetryApiIssue.apiSourceMissing,
        runtime == null
            ? 'Python 3 was not found. Install Python or use a bundled runtime.'
            : 'Telemetry API files are missing from this installation.',
      );
      return;
    }
    if (!await _acquireLock()) {
      await _fail(
        TelemetryApiStatus.reconnecting,
        TelemetryApiIssue.anotherInstanceStarting,
        'Another AURA instance is managing the telemetry service.',
      );
      return;
    }
    await _launch(source: source, runtime: runtime);
  }

  Future<void> _stopCurrentProcess(int generation) async {
    if (generation != _generation) return;
    _generation++;
    final TelemetryManagedProcess? process = _process;
    _process = null;
    if (process == null) return;
    await process.terminate();
    await process.dispose();
    await _outputSubscription?.cancel();
    _outputSubscription = null;
    await _releaseLock();
  }

  void _handleOutput(String line) {
    final String lower = line.toLowerCase();
    if (lower.contains('address already in use') ||
        lower.contains('winerror 10048')) {
      _exitHint = TelemetryProcessExitKind.portOccupied;
    } else if (lower.contains('modulenotfounderror') ||
        lower.contains('no module named')) {
      _exitHint = TelemetryProcessExitKind.missingDependency;
    } else if (lower.contains('traceback') || lower.contains('error:')) {
      _exitHint = TelemetryProcessExitKind.pythonError;
    }
    unawaited(logStore.append('python output', detail: line));
  }

  Future<bool> _acquireLock() async {
    if (!lockDirectory.existsSync()) {
      await lockDirectory.create(recursive: true);
    }
    final File file = File(
      '${lockDirectory.path}${Platform.pathSeparator}telemetry_api.lock',
    );
    try {
      if (file.existsSync()) {
        final DateTime modified = (await file.stat()).modified;
        final Duration allowed =
            config.startupTimeout + const Duration(seconds: 5);
        if (DateTime.now().difference(modified) < allowed) return false;
        await file.delete();
      }
      final RandomAccessFile handle = await file.open(mode: FileMode.writeOnly);
      try {
        _lockToken = DateTime.now().microsecondsSinceEpoch.toString();
        await handle.writeString(_lockToken!);
      } finally {
        await handle.close();
      }
      _lockFile = file;
      return true;
    } on Object {
      _lockFile = null;
      _lockToken = null;
      return false;
    }
  }

  Future<void> _releaseLock() async {
    final File? file = _lockFile;
    final String? token = _lockToken;
    _lockFile = null;
    _lockToken = null;
    if (file == null || !file.existsSync()) return;
    try {
      final String content = await file.readAsString();
      if (token == null || content.trim() == token) {
        await file.delete();
      }
    } on Object {
      // Stale lock files are cleared on the next acquisition.
    }
  }

  Future<void> _log(String event, {String? detail}) =>
      logStore.append(event, detail: detail);

  Future<void> _fail(
    TelemetryApiStatus status,
    TelemetryApiIssue issue,
    String message, {
    String? detail,
  }) async {
    _set(
      status,
      issue,
      message,
      managedProcessRunning: _process != null,
    );
    await _log('startup failed',
        detail: '$issue${detail == null ? '' : ': $detail'}');
  }

  void _set(
    TelemetryApiStatus status,
    TelemetryApiIssue issue,
    String message, {
    bool? managedProcessRunning,
  }) {
    if (!mounted) return;
    state = TelemetryApiState(
      status: status,
      issue: issue,
      message: message,
      lastCheckedAt: DateTime.now(),
      restartAttempts: _restartAttempts,
      managedProcessRunning:
          managedProcessRunning ?? state.managedProcessRunning,
    );
  }

  @override
  Future<void> dispose() async {
    await shutdown();
    super.dispose();
  }
}
