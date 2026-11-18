import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_probe.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_service.dart';
import 'package:aura_hub/core/telemetry/telemetry_log_store.dart';
import 'package:aura_hub/core/telemetry/telemetry_process.dart';
import 'package:aura_hub/core/telemetry/telemetry_runtime_locator.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeProbe implements TelemetryApiProbe {
  FakeProbe(this._initial);

  final Queue<TelemetryHealthResult> _queue = Queue<TelemetryHealthResult>();
  final TelemetryHealthResult _initial;
  TelemetryHealthResult _fallback = TelemetryHealthResult.unreachable;
  int checks = 0;
  bool shutdownRequested = false;
  Future<void> Function()? onShutdown;

  void thenHealthy() => _fallback = TelemetryHealthResult.healthyResult;

  void enqueue(TelemetryHealthResult result) => _queue.add(result);

  @override
  Future<TelemetryHealthResult> check() async {
    checks++;
    if (_queue.isNotEmpty) return _queue.removeFirst();
    if (checks == 1) return _initial;
    return _fallback;
  }

  @override
  Future<bool> requestShutdown() async {
    shutdownRequested = true;
    final Future<void> Function()? hook = onShutdown;
    if (hook != null) await hook();
    return true;
  }
}

class LaunchCall {
  LaunchCall({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
    required this.process,
  });

  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final Map<String, String> environment;
  final FakeProcess process;
}

class FakeLauncher implements TelemetryProcessLauncher {
  final List<LaunchCall> calls = <LaunchCall>[];
  Future<void> Function(LaunchCall call)? onLaunch;

  @override
  Future<TelemetryManagedProcess> launch({
    required String executable,
    required List<String> arguments,
    required String workingDirectory,
    Map<String, String> environment = const <String, String>{},
  }) async {
    final FakeProcess process = FakeProcess(pid: 4100 + calls.length);
    final LaunchCall call = LaunchCall(
      executable: executable,
      arguments: arguments,
      workingDirectory: workingDirectory,
      environment: environment,
      process: process,
    );
    calls.add(call);
    final Future<void> Function(LaunchCall call)? hook = onLaunch;
    if (hook != null) await hook(call);
    return process;
  }
}

class FakeProcess implements TelemetryManagedProcess {
  FakeProcess({required this.pid});

  @override
  final int pid;

  final Completer<int> _exit = Completer<int>();
  final StreamController<String> _output = StreamController<String>.broadcast();
  bool _exited = false;
  int terminateCalls = 0;
  int disposeCalls = 0;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  Stream<String> get output => _output.stream;

  @override
  bool get jobGuardActive => false;

  void emit(String line) {
    if (!_output.isClosed) _output.add(line);
  }

  void exit(int code) {
    if (_exited) return;
    _exited = true;
    _exit.complete(code);
  }

  @override
  Future<bool> waitForExit(Duration timeout) async {
    if (_exited || _exit.isCompleted) return true;
    return _exit.future
        .then<bool>((_) => true)
        .timeout(timeout, onTimeout: () => false);
  }

  @override
  Future<void> terminate() async {
    terminateCalls++;
    exit(-1);
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await _output.close();
  }
}

class FakeRuntimeLocator extends TelemetryRuntimeLocator {
  FakeRuntimeLocator(this.runtime) : super(searchRoots: const <Directory>[]);

  final TelemetryRuntime? runtime;

  @override
  Future<TelemetryRuntime?> locate() async => runtime;
}

class FakeSourceLocator extends TelemetryApiSourceLocator {
  FakeSourceLocator(this.source) : super(searchRoots: const <Directory>[]);

  final TelemetryApiSource? source;

  @override
  TelemetryApiSource? locate() => source;
}

class RecordingLogStore extends TelemetryApiLogStore {
  RecordingLogStore(Directory directory) : super(directory: directory);

  final List<String> events = <String>[];

  @override
  Future<void> append(String event, {String? detail}) async {
    events.add(detail == null ? event : '$event: $detail');
    await super.append(event, detail: detail);
  }

  @override
  void appendSync(String event, {String? detail}) {
    events.add(detail == null ? event : '$event: $detail');
    super.appendSync(event, detail: detail);
  }
}

void main() {
  late Directory root;
  late TelemetryApiSource source;
  late FakeProbe probe;
  late FakeLauncher launcher;
  late RecordingLogStore logStore;
  late TelemetryApiService service;

  TelemetryApiConfig config() => TelemetryApiConfig(
        host: '127.0.0.1',
        port: 8765,
        startupTimeout: const Duration(milliseconds: 250),
        healthPollInterval: const Duration(milliseconds: 10),
        healthTimeout: const Duration(milliseconds: 20),
        restartBackoff: const Duration(milliseconds: 10),
        maxRestartAttempts: 1,
        shutdownTimeout: const Duration(milliseconds: 20),
      );

  TelemetryApiService buildService({
    TelemetryApiConfig? overrideConfig,
    bool missingRuntime = false,
    TelemetryApiSource? apiSource,
  }) {
    return TelemetryApiService(
      config: overrideConfig ?? config(),
      probe: probe,
      launcher: launcher,
      runtimeLocator: FakeRuntimeLocator(
        missingRuntime
            ? null
            : const TelemetryRuntime(
                executable: 'pythonw.exe',
                source: 'test',
              ),
      ),
      sourceLocator: FakeSourceLocator(apiSource ?? source),
      logStore: logStore,
      lockDirectory: root,
    );
  }

  setUp(() {
    root = Directory.systemTemp.createTempSync('aura-telemetry-service-test-');
    final File entry = File('${root.path}${Platform.pathSeparator}aura_api.py');
    entry.writeAsStringSync('pass\n');
    source = TelemetryApiSource(
      root: root,
      entryPoint: entry,
      workingDirectory: root,
    );
    probe = FakeProbe(TelemetryHealthResult.unreachable);
    launcher = FakeLauncher();
    logStore = RecordingLogStore(root);
  });

  tearDown(() async {
    await service.shutdown();
    root.deleteSync(recursive: true);
  });

  test('healthy API is reused without launching another process', () async {
    probe = FakeProbe(TelemetryHealthResult.healthyResult);
    service = buildService();

    await service.start();

    expect(service.state.status, TelemetryApiStatus.online);
    expect(service.state.managedProcessRunning, isFalse);
    expect(launcher.calls, isEmpty);
    expect(logStore.events, contains('reused healthy API: external process'));
  });

  test('unavailable API is started with real request arguments', () async {
    launcher.onLaunch = (LaunchCall call) async {
      call.process.emit('AURA telemetry API listening');
      probe.thenHealthy();
    };
    service = buildService();

    await service.start();

    expect(service.state.status, TelemetryApiStatus.online);
    expect(service.state.managedProcessRunning, isTrue);
    expect(launcher.calls, hasLength(1));
    final LaunchCall call = launcher.calls.single;
    expect(call.executable, 'pythonw.exe');
    expect(call.arguments, contains('-u'));
    expect(call.arguments, contains(source.entryPoint.path));
    expect(call.environment['AURA_API_HOST'], '127.0.0.1');
    expect(call.environment['AURA_API_PORT'], '8765');
    expect(call.workingDirectory, root.path);
    expect(logStore.events, contains(startsWith('process started:')));
  });

  test('startup timeout stops the app-managed process', () async {
    service = buildService();

    await service.start();

    expect(service.state.status, TelemetryApiStatus.startupFailed);
    expect(service.state.issue, TelemetryApiIssue.startupTimeout);
    expect(launcher.calls, hasLength(1));
    expect(
        launcher.calls.single.process.terminateCalls, greaterThanOrEqualTo(1));
    expect(
      File('${root.path}${Platform.pathSeparator}telemetry_api.lock')
          .existsSync(),
      isFalse,
    );
  });

  test('missing Python runtime is reported without launching', () async {
    service = buildService(missingRuntime: true);

    await service.start();

    expect(service.state.status, TelemetryApiStatus.startupFailed);
    expect(service.state.issue, TelemetryApiIssue.runtimeMissing);
    expect(launcher.calls, isEmpty);
  });

  test('unexpected process exit after startup is recovered once', () async {
    late FakeProcess firstProcess;
    launcher.onLaunch = (LaunchCall call) async {
      probe.thenHealthy();
      if (launcher.calls.length == 1) {
        firstProcess = call.process;
      }
    };
    service = buildService();

    await service.start();
    expect(service.state.status, TelemetryApiStatus.online);

    firstProcess.emit('Traceback (most recent call last)');
    firstProcess.exit(1);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(launcher.calls, hasLength(2));
    expect(service.state.status, TelemetryApiStatus.online);
    expect(service.state.restartAttempts, 1);
    expect(logStore.events, contains(startsWith('unexpected exit:')));
  });

  test('fresh lock prevents duplicate process startup', () async {
    final File lock =
        File('${root.path}${Platform.pathSeparator}telemetry_api.lock');
    await lock.writeAsString('another-instance');
    service = buildService();

    await service.start();

    expect(service.state.status, TelemetryApiStatus.startupFailed);
    expect(service.state.issue, TelemetryApiIssue.anotherInstanceStarting);
    expect(launcher.calls, isEmpty);
  });

  test('shutdown requests graceful stop and releases the lock', () async {
    launcher.onLaunch = (LaunchCall call) async {
      probe.thenHealthy();
      probe.onShutdown = () async => call.process.exit(0);
    };
    service = buildService();
    await service.start();
    expect(service.state.status, TelemetryApiStatus.online);

    await service.shutdown();

    expect(probe.shutdownRequested, isTrue);
    expect(logStore.events, contains(startsWith('shutdown requested:')));
    expect(logStore.events, contains(startsWith('shutdown complete:')));
    expect(service.state.status, TelemetryApiStatus.offline);
    expect(
      File('${root.path}${Platform.pathSeparator}telemetry_api.lock')
          .existsSync(),
      isFalse,
    );
  });

  test('unrelated service on the port is never stopped', () async {
    probe = FakeProbe(TelemetryHealthResult.unrelatedService);
    service = buildService();

    await service.start();

    expect(service.state.status, TelemetryApiStatus.startupFailed);
    expect(service.state.issue, TelemetryApiIssue.portOccupied);
    expect(launcher.calls, isEmpty);
    expect(probe.shutdownRequested, isFalse);
  });

  test('start is disabled for non-loopback endpoints', () async {
    service = buildService(
      overrideConfig: config().copyWith(host: '10.0.0.5', autoStart: false),
    );

    await service.start();

    expect(service.state.status, TelemetryApiStatus.offline);
    expect(service.state.issue, TelemetryApiIssue.disabled);
    expect(launcher.calls, isEmpty);
  });
}
