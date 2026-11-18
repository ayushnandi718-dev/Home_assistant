import 'dart:async';
import 'dart:io';

/// Redacts values that must never reach a telemetry service log file.
///
/// This is deliberately conservative: raw Python output is untrusted and may
/// contain credentials, PINs, local paths or telemetry payloads. Only a small,
/// sanitized excerpt is retained for troubleshooting.
String redactTelemetryLogText(String input) {
  String text = input.replaceAll('\r', ' ').replaceAll('\n', ' ').trim();
  // Bearer values are handled first so a preceding "Authorization:" label
  // cannot consume the scheme and leave the token behind.
  text = text.replaceAllMapped(
    RegExp(r'\bBearer\s+\S+', caseSensitive: false),
    (Match _) => 'Bearer [REDACTED]',
  );
  text = text.replaceAllMapped(
    RegExp(
      r'\b(api[_-]?key|access[_-]?token|refresh[_-]?token|token|authorization|password|passphrase|pin)\b\s*[:=]\s*(?!Bearer\b)[\x22\x27]?[^\x22\x27\s,;]+',
      caseSensitive: false,
    ),
    (Match match) => '${match.group(1)}=[REDACTED]',
  );
  text = text.replaceAll(RegExp(r'https?://\S+'), '[URL]');
  text = text.replaceAllMapped(
    RegExp(r'\b([A-Z]:\\Users\\)[^\\]+', caseSensitive: false),
    (Match match) => '${match.group(1)}[USER]',
  );
  text = text.replaceAllMapped(
    RegExp(r'(/home/|/Users/)[^/\s]+', caseSensitive: false),
    (Match match) => '${match.group(1)}[USER]',
  );
  text = text.replaceAll(RegExp(r'\b\d{6,}\b'), '[NUMBER]');
  if (text.length > 400) {
    text = '${text.substring(0, 400)}…';
  }
  return text;
}

/// Small rotating log store for the app-managed telemetry process.
///
/// Writes are serialized so Python stdout/stderr callbacks and lifecycle events
/// cannot interleave partial lines.
class TelemetryApiLogStore {
  TelemetryApiLogStore({
    required this.directory,
    this.fileName = 'telemetry_api.log',
    this.maxBytes = 512 * 1024,
    this.maxFiles = 3,
  });

  final Directory directory;
  final String fileName;
  final int maxBytes;
  final int maxFiles;

  Future<void> _queue = Future<void>.value();

  File get _activeFile =>
      File('${directory.path}${Platform.pathSeparator}$fileName');

  Future<void> append(String event, {String? detail}) async {
    final String line = _formatLine(event, detail);
    final Future<void> next = _queue.then((_) => _writeLine(line));
    _queue = next.catchError((Object _) {});
    await next;
  }

  /// Writes one line before returning.
  ///
  /// Used for shutdown events, where the app process may exit before queued
  /// asynchronous writes can complete. The Windows job handle remains the final
  /// guarantee that the child process is reaped even if this write is missed.
  void appendSync(String event, {String? detail}) {
    final String line = _formatLine(event, detail);
    try {
      if (!directory.existsSync()) {
        directory.createSync(recursive: true);
      }
      _rotateIfNeededSync();
      final RandomAccessFile handle =
          _activeFile.openSync(mode: FileMode.append);
      try {
        handle.writeStringSync('$line\n');
      } finally {
        handle.closeSync();
      }
    } on Object {
      // Logging is best-effort; it must never prevent shutdown.
    }
  }

  String _formatLine(String event, String? detail) {
    final String safeEvent = redactTelemetryLogText(event);
    final String? safeDetail = detail == null || detail.trim().isEmpty
        ? null
        : redactTelemetryLogText(detail);
    return safeDetail == null
        ? '${DateTime.now().toIso8601String()} $safeEvent'
        : '${DateTime.now().toIso8601String()} $safeEvent: $safeDetail';
  }

  /// Newest-first sanitized lines, including rotated files.
  Future<List<String>> readRecent({int limit = 80}) async {
    if (limit <= 0) return const <String>[];
    final List<String> lines = <String>[];
    for (int index = 0; index < maxFiles && lines.length < limit; index++) {
      final File file = index == 0 ? _activeFile : _rotatedFile(index);
      if (!file.existsSync()) continue;
      try {
        final List<String> fileLines = await file.readAsLines();
        for (final String line in fileLines.reversed) {
          if (line.trim().isEmpty) continue;
          lines.add(redactTelemetryLogText(line));
          if (lines.length >= limit) break;
        }
      } on Object {
        // A truncated or locked log file must never break the UI.
      }
    }
    return lines;
  }

  File _rotatedFile(int index) => File('${_activeFile.path}.$index');

  Future<void> _writeLine(String line) async {
    try {
      if (!directory.existsSync()) {
        await directory.create(recursive: true);
      }
      await _rotateIfNeeded();
      final RandomAccessFile handle =
          await _activeFile.open(mode: FileMode.append);
      try {
        await handle.writeString('$line\n');
      } finally {
        await handle.close();
      }
    } on Object {
      // Logging is best-effort; it must never prevent API startup or shutdown.
    }
  }

  Future<void> _rotateIfNeeded() async {
    if (!_activeFile.existsSync()) return;
    if (await _activeFile.length() < maxBytes) return;
    if (maxFiles <= 1) {
      await _activeFile.delete();
      return;
    }

    // Shift .1 -> .2 -> ... -> .(maxFiles - 1), then move active -> .1.
    for (int index = maxFiles - 1; index >= 2; index--) {
      final File destination = _rotatedFile(index);
      if (destination.existsSync()) {
        await destination.delete();
      }
      final File source = _rotatedFile(index - 1);
      if (source.existsSync()) {
        await source.rename(destination.path);
      }
    }
    final File first = _rotatedFile(1);
    if (first.existsSync()) await first.delete();
    if (_activeFile.existsSync()) {
      await _activeFile.rename(first.path);
    }
  }

  void _rotateIfNeededSync() {
    if (!_activeFile.existsSync()) return;
    if (_activeFile.lengthSync() < maxBytes) return;
    if (maxFiles <= 1) {
      _activeFile.deleteSync();
      return;
    }

    for (int index = maxFiles - 1; index >= 2; index--) {
      final File destination = _rotatedFile(index);
      if (destination.existsSync()) {
        destination.deleteSync();
      }
      final File source = _rotatedFile(index - 1);
      if (source.existsSync()) {
        source.renameSync(destination.path);
      }
    }
    final File first = _rotatedFile(1);
    if (first.existsSync()) first.deleteSync();
    if (_activeFile.existsSync()) {
      _activeFile.renameSync(first.path);
    }
  }
}
