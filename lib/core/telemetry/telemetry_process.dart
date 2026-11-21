import 'dart:async';
import 'dart:convert';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/core/telemetry/windows_process_guard.dart';

/// A child process owned by AURA Hub. Implementations are intentionally small
/// so lifecycle behaviour can be tested without launching Python.
abstract class TelemetryManagedProcess {
  int get pid;

  Future<int> get exitCode;

  Future<bool> waitForExit(Duration timeout);

  /// Whether the Windows job guard is protecting this exact child process.
  bool get jobGuardActive => false;

  /// Last-resort termination of the process AURA Hub started.
  Future<void> terminate();

  Future<void> dispose();

  Stream<String> get output;
}

class TelemetryProcessLaunchException implements Exception {
  const TelemetryProcessLaunchException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'TelemetryProcessLaunchException: $message';
}

/// Launches the Python API as a hidden child process.
abstract class TelemetryProcessLauncher {
  Future<TelemetryManagedProcess> launch({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const <String, String>{},
  });
}

class DartTelemetryProcessLauncher implements TelemetryProcessLauncher {
  const DartTelemetryProcessLauncher();

  @override
  Future<TelemetryManagedProcess> launch({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const <String, String>{},
  }) async {
    try {
      // The runtime locator prefers pythonw.exe on Windows, whose GUI subsystem
      // creates no console window. Dart's Process.start has no windowsHide flag.
      final Process process = await Process.start(
        executable,
        arguments,
        workingDirectory: workingDirectory,
        environment: <String, String>{
          'PYTHONUNBUFFERED': '1',
          ...environment,
        },
        includeParentEnvironment: true,
      );
      return DartTelemetryManagedProcess(process);
    } on Object catch (error) {
      throw TelemetryProcessLaunchException(
        'The telemetry API process could not be started.',
        cause: error,
      );
    }
  }
}

/// Wraps a real [Process] and, on Windows, assigns it to an app-owned job so
/// the OS terminates it if AURA Hub disappears unexpectedly.
class DartTelemetryManagedProcess implements TelemetryManagedProcess {
  DartTelemetryManagedProcess(this._process) {
    _guard = WindowsProcessGuard.attach(_process.pid);
    _exitFuture = _process.exitCode.then<int>((int code) {
      _exited = true;
      return code;
    });
    final StreamController<String> controller =
        StreamController<String>.broadcast();
    _output = controller.stream;
    int pending = 0;

    void complete() {
      pending--;
      if (pending <= 0 && !controller.isClosed) controller.close();
    }

    void pump(Stream<List<int>>? source) {
      if (source == null) {
        complete();
        return;
      }
      source.transform(utf8.decoder).transform(const LineSplitter()).listen(
        controller.add,
        onError: (Object error) {
          if (!controller.isClosed) controller.addError(error);
          complete();
        },
        onDone: complete,
        cancelOnError: true,
      );
    }

    pending = 2;
    pump(_process.stdout);
    pump(_process.stderr);
  }

  final Process _process;
  late final WindowsProcessGuard? _guard;
  late final Future<int> _exitFuture;
  late final Stream<String> _output;
  bool _exited = false;
  bool _disposed = false;

  @override
  int get pid => _process.pid;

  @override
  Future<int> get exitCode => _exitFuture;

  @override
  Stream<String> get output => _output;

  @override
  bool get jobGuardActive => _guard?.isActive ?? false;

  @override
  Future<bool> waitForExit(Duration timeout) async {
    if (_exited) return true;
    return _exitFuture
        .then<bool>((_) => true)
        .timeout(timeout, onTimeout: () => false);
  }

  @override
  Future<void> terminate() async {
    if (_exited) return;
    final WindowsProcessGuard? guard = _guard;
    if (guard != null && guard.isActive) {
      guard.terminate();
      return;
    }
    try {
      final bool killed = _process.kill();
      if (!killed && !_exited) {
        // On Windows a false result can mean the process exited concurrently.
        await waitForExit(const Duration(milliseconds: 200));
      }
    } on Object {
      // Best effort: the project exit future still completes.
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _guard?.dispose();
  }
}
