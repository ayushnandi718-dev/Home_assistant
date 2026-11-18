import 'dart:io';

import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';

/// Discovers a usable Python runtime without assuming a fixed install path.
///
/// Search order is: explicit override, app-local virtual environments/bundled
/// runtimes, then PATH. Every candidate is executed once with a harmless probe
/// so a missing or broken interpreter is reported before the API is launched.
class TelemetryRuntimeLocator {
  const TelemetryRuntimeLocator({
    List<Directory>? searchRoots,
    Map<String, String>? environment,
    this.probeTimeout = const Duration(seconds: 3),
  })  : _searchRoots = searchRoots,
        _environment = environment;

  final List<Directory>? _searchRoots;
  final Map<String, String>? _environment;
  final Duration probeTimeout;

  Future<TelemetryRuntime?> locate() async {
    final Map<String, String> environment =
        _environment ?? Platform.environment;
    final String? override = environment['AURA_TELEMETRY_PYTHON']?.trim();
    if (override != null && override.isNotEmpty) {
      final List<String> args = _splitArgs(
        environment['AURA_TELEMETRY_PYTHON_ARGS'],
      );
      if (await _canRun(override, args)) {
        return TelemetryRuntime(
          executable: override,
          prefixArguments: args,
          source: 'override',
        );
      }
    }

    for (final Directory root in _roots()) {
      for (final String relative in appLocalCandidates) {
        final File candidate =
            File('${root.path}${Platform.pathSeparator}$relative');
        if (!candidate.existsSync()) continue;
        if (await _canRun(candidate.path, const <String>[])) {
          return TelemetryRuntime(
            executable: candidate.path,
            source: 'app-local',
          );
        }
      }
    }

    for (final String executable in pathCandidates) {
      if (await _canRun(executable, const <String>[])) {
        return TelemetryRuntime(
          executable: executable,
          source: 'PATH',
        );
      }
    }
    return null;
  }

  /// On Windows only GUI-subsystem interpreters are used, so no console window
  /// is ever created. A console interpreter can still be forced explicitly via
  /// `AURA_TELEMETRY_PYTHON` for debugging.
  static List<String> get appLocalCandidates => Platform.isWindows
      ? const <String>[
          'server/.venv/Scripts/pythonw.exe',
          '.venv/Scripts/pythonw.exe',
          'venv/Scripts/pythonw.exe',
          'runtime/python/pythonw.exe',
          'runtime/Python/pythonw.exe',
          'python/pythonw.exe',
        ]
      : const <String>[
          'server/.venv/bin/python3',
          '.venv/bin/python3',
          'venv/bin/python3',
          'runtime/python/bin/python3',
        ];

  static List<String> get pathCandidates => Platform.isWindows
      ? const <String>['pythonw.exe']
      : const <String>['python3', 'python'];

  List<Directory> _roots() {
    final List<Directory>? configured = _searchRoots;
    if (configured != null) return List<Directory>.from(configured);
    final List<Directory> roots = <Directory>[Directory.current];
    try {
      roots.add(File(Platform.resolvedExecutable).parent);
    } on Object {
      // Keep the working directory as the only root when executable lookup is
      // unavailable in a test environment.
    }
    final Set<String> seen = <String>{};
    final List<Directory> result = <Directory>[];
    for (final Directory start in roots) {
      Directory? current = start;
      while (current != null) {
        final String path = current.path.replaceAll('\\', '/');
        if (seen.add(path)) result.add(current);
        final Directory parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return result;
  }

  Future<bool> _canRun(String executable, List<String> args) async {
    try {
      final Process process = await Process.start(
        executable,
        <String>[...args, '-c', 'pass'],
        includeParentEnvironment: true,
      );
      await process.stdin.close();
      final int code = await process.exitCode.timeout(
        probeTimeout,
        onTimeout: () {
          process.kill();
          return -1;
        },
      );
      await process.stdout.drain<void>();
      await process.stderr.drain<void>();
      return code == 0;
    } on Object {
      return false;
    }
  }

  static List<String> _splitArgs(String? value) {
    final String raw = value?.trim() ?? '';
    if (raw.isEmpty) return const <String>[];
    return raw
        .split(RegExp(r'\s+'))
        .where((String part) => part.isNotEmpty)
        .toList();
  }
}

/// Locates the bundled or source-tree telemetry API files.
class TelemetryApiSourceLocator {
  const TelemetryApiSourceLocator({
    List<Directory>? searchRoots,
    List<String>? entryPointCandidates,
  })  : _searchRoots = searchRoots,
        _entryPointCandidates = entryPointCandidates;

  final List<Directory>? _searchRoots;
  final List<String>? _entryPointCandidates;

  static const List<String> defaultEntryPoints = <String>[
    'server/aura_api.py',
    'telemetry_api/main.py',
    'telemetry_api/app.py',
    'telemetry_api/api.py',
    'telemetry_api/server.py',
    'api/telemetry_api.py',
    'api/main.py',
    'api.py',
  ];

  TelemetryApiSource? locate() {
    for (final Directory root in _roots()) {
      for (final String relative
          in _entryPointCandidates ?? defaultEntryPoints) {
        final File entry =
            File('${root.path}${Platform.pathSeparator}$relative');
        if (!entry.existsSync()) continue;
        return TelemetryApiSource(
          root: entry.parent,
          entryPoint: entry,
          workingDirectory: root,
        );
      }
    }
    return null;
  }

  List<Directory> _roots() {
    final List<Directory>? configured = _searchRoots;
    if (configured != null) return List<Directory>.from(configured);
    final List<Directory> roots = <Directory>[Directory.current];
    try {
      roots.add(File(Platform.resolvedExecutable).parent);
    } on Object {
      // Ignore unavailable executable paths.
    }
    final Set<String> seen = <String>{};
    final List<Directory> result = <Directory>[];
    for (final Directory start in roots) {
      Directory? current = start;
      while (current != null) {
        final String key = current.path.replaceAll('\\', '/');
        if (seen.add(key)) result.add(current);
        final Directory parent = current.parent;
        if (parent.path == current.path) break;
        current = parent;
      }
    }
    return result;
  }
}
