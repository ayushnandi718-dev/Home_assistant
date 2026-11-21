import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

final Map<String, Uint8List> _webFiles = <String, Uint8List>{};
final Map<String, DateTime> _webModified = <String, DateTime>{};
final Set<String> _webDirectories = <String>{'.'};

String _webPath(String path) {
  final String normalized = path.replaceAll('\\', '/').trim();
  if (normalized.isEmpty || normalized == '.') return '.';
  if (normalized == '/') return '/';
  final String withoutTrailing =
      normalized.endsWith('/') && normalized.length > 1
          ? normalized.substring(0, normalized.length - 1)
          : normalized;
  return withoutTrailing;
}

String _webParent(String path) {
  final int slash = path.lastIndexOf('/');
  if (slash < 0) return '.';
  if (slash == 0) return '/';
  return path.substring(0, slash);
}

String _webName(String path) {
  final int slash = path.lastIndexOf('/');
  return slash < 0 ? path : path.substring(slash + 1);
}

void _webTouch(String path) {
  _webModified[path] = DateTime.now();
}

class Platform {
  static const bool isAndroid = false;
  static const bool isIOS = false;
  static const bool isLinux = false;
  static const bool isMacOS = false;
  static const bool isWindows = false;
  static const bool isFuchsia = false;
  static const String pathSeparator = '/';
  static const String lineSeparator = '\n';
  static const String localeName = 'en_US';
  static const String version = 'web';
  static const String resolvedExecutable = 'aura_hub/web';
  // Keep the hidden local telemetry service from starting a Python process in
  // the browser. Local process execution is not available on the web.
  static const Map<String, String> environment = <String, String>{
    'AURA_TELEMETRY_AUTOSTART': 'false',
  };
}

abstract class IOException implements Exception {
  const IOException();
}

class FileSystemException implements IOException {
  const FileSystemException([this.message = '', this.path, this.osError]);

  final String message;
  final String? path;
  final Object? osError;

  @override
  String toString() => path == null
      ? 'FileSystemException: $message'
      : 'FileSystemException: $message, path = $path';
}

class SocketException implements IOException {
  const SocketException(this.message, {this.osError});

  final String message;
  final Object? osError;

  @override
  String toString() => 'SocketException: $message';
}

class HttpException implements IOException {
  const HttpException(this.message);

  final String message;

  @override
  String toString() => 'HttpException: $message';
}

class HandshakeException implements IOException {
  const HandshakeException(this.message);

  final String message;

  @override
  String toString() => 'HandshakeException: $message';
}

class TlsException implements IOException {
  const TlsException(this.message);

  final String message;

  @override
  String toString() => 'TlsException: $message';
}

enum FileMode { read, write, writeOnly, append }

abstract class FileSystemEntity {
  String get path;
  bool existsSync();
  Future<bool> exists();
  Future<void> delete();
  void deleteSync();
}

class FileStat {
  const FileStat._(
    this.size,
    this.modified,
    this.changed,
    this.accessed,
    this.type,
  );

  final int size;
  final DateTime modified;
  final DateTime changed;
  final DateTime accessed;
  final FileSystemEntityType type;
}

enum FileSystemEntityType { file, directory, link, notFound }

class File implements FileSystemEntity {
  File(String path) : path = _webPath(path);

  @override
  final String path;

  @override
  String toString() => "File: '$path'";

  String get name => _webName(path);

  Directory get parent => Directory(_webParent(path));

  @override
  bool existsSync() => _webFiles.containsKey(path);

  @override
  Future<bool> exists() async => existsSync();

  Future<File> create({bool recursive = false}) async {
    if (recursive) await parent.create(recursive: true);
    _webFiles.putIfAbsent(path, () => Uint8List(0));
    _webTouch(path);
    return this;
  }

  File createSync({bool recursive = false}) {
    if (recursive) parent.createSync(recursive: true);
    _webFiles.putIfAbsent(path, () => Uint8List(0));
    _webTouch(path);
    return this;
  }

  Future<List<int>> readAsBytes() async {
    final Uint8List? bytes = _webFiles[path];
    if (bytes == null) {
      throw FileSystemException('Cannot read a missing file', path);
    }
    return Uint8List.fromList(bytes);
  }

  List<int> readAsBytesSync() {
    final Uint8List? bytes = _webFiles[path];
    if (bytes == null) {
      throw FileSystemException('Cannot read a missing file', path);
    }
    return Uint8List.fromList(bytes);
  }

  Future<String> readAsString({Encoding encoding = utf8}) async =>
      encoding.decode(await readAsBytes());

  String readAsStringSync({Encoding encoding = utf8}) =>
      encoding.decode(readAsBytesSync());

  Future<List<String>> readAsLines({Encoding encoding = utf8}) async =>
      const LineSplitter().convert(await readAsString(encoding: encoding));

  Future<int> length() async => (await readAsBytes()).length;

  int lengthSync() => readAsBytesSync().length;

  Future<DateTime> lastModified() async =>
      _webModified[path] ?? DateTime.fromMillisecondsSinceEpoch(0);

  DateTime lastModifiedSync() =>
      _webModified[path] ?? DateTime.fromMillisecondsSinceEpoch(0);

  Future<FileStat> stat() async {
    final DateTime modified = await lastModified();
    return FileStat._(await length(), modified, modified, modified,
        FileSystemEntityType.file);
  }

  Future<File> writeAsBytes(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) async {
    await parent.create(recursive: true);
    final Uint8List incoming = Uint8List.fromList(bytes);
    if (mode == FileMode.append && _webFiles.containsKey(path)) {
      final Uint8List previous = _webFiles[path]!;
      _webFiles[path] = Uint8List.fromList(<int>[...previous, ...incoming]);
    } else {
      _webFiles[path] = incoming;
    }
    _webTouch(path);
    return this;
  }

  File writeAsBytesSync(
    List<int> bytes, {
    FileMode mode = FileMode.write,
    bool flush = false,
  }) {
    parent.createSync(recursive: true);
    final Uint8List incoming = Uint8List.fromList(bytes);
    if (mode == FileMode.append && _webFiles.containsKey(path)) {
      final Uint8List previous = _webFiles[path]!;
      _webFiles[path] = Uint8List.fromList(<int>[...previous, ...incoming]);
    } else {
      _webFiles[path] = incoming;
    }
    _webTouch(path);
    return this;
  }

  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      writeAsBytes(encoding.encode(contents), mode: mode, flush: flush);

  File writeAsStringSync(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) =>
      writeAsBytesSync(encoding.encode(contents), mode: mode, flush: flush);

  Future<RandomAccessFile> open({FileMode mode = FileMode.read}) async {
    await parent.create(recursive: true);
    return RandomAccessFile._(path, mode);
  }

  RandomAccessFile openSync({FileMode mode = FileMode.read}) =>
      RandomAccessFile._(path, mode);

  Future<File> rename(String newPath) async {
    final Uint8List? bytes = _webFiles[path];
    if (bytes == null) {
      throw FileSystemException('Cannot rename a missing file', path);
    }
    final String target = _webPath(newPath);
    await File(target).parent.create(recursive: true);
    _webFiles[target] = bytes;
    _webTouch(target);
    _webFiles.remove(path);
    return File(target);
  }

  File renameSync(String newPath) {
    final Uint8List? bytes = _webFiles[path];
    if (bytes == null) {
      throw FileSystemException('Cannot rename a missing file', path);
    }
    final String target = _webPath(newPath);
    File(target).parent.createSync(recursive: true);
    _webFiles[target] = bytes;
    _webTouch(target);
    _webFiles.remove(path);
    return File(target);
  }

  Future<File> copy(String newPath) async {
    final Uint8List? bytes = _webFiles[path];
    if (bytes == null) {
      throw FileSystemException('Cannot copy a missing file', path);
    }
    final String target = _webPath(newPath);
    await File(target).parent.create(recursive: true);
    _webFiles[target] = Uint8List.fromList(bytes);
    _webTouch(target);
    return File(target);
  }

  File copySync(String newPath) {
    final Uint8List? bytes = _webFiles[path];
    if (bytes == null) {
      throw FileSystemException('Cannot copy a missing file', path);
    }
    final String target = _webPath(newPath);
    File(target).parent.createSync(recursive: true);
    _webFiles[target] = Uint8List.fromList(bytes);
    _webTouch(target);
    return File(target);
  }

  @override
  Future<void> delete() async {
    _webFiles.remove(path);
    _webModified.remove(path);
  }

  @override
  void deleteSync() {
    _webFiles.remove(path);
    _webModified.remove(path);
  }
}

class Directory implements FileSystemEntity {
  factory Directory(String path) => Directory._(_webPath(path));

  Directory._(this.path);

  static Directory get current => Directory('.');

  static Directory get systemTemp => Directory('/temp');

  @override
  final String path;

  @override
  String toString() => "Directory: '$path'";

  String get name => _webName(path);

  Directory get parent => Directory(_webParent(path));

  @override
  bool existsSync() =>
      _webDirectories.contains(path) ||
      _webFiles.keys.any((String key) => key.startsWith('$path/'));

  @override
  Future<bool> exists() async => existsSync();

  Future<Directory> create({bool recursive = false}) async {
    if (recursive) {
      final List<String> parts = path.split('/');
      String current = path.startsWith('/') ? '' : '';
      for (final String part in parts) {
        if (part.isEmpty) continue;
        current = current.isEmpty
            ? (path.startsWith('/') ? '/$part' : part)
            : '$current/$part';
        _webDirectories.add(current);
      }
    }
    _webDirectories.add(path);
    return this;
  }

  Directory createSync({bool recursive = false}) {
    if (recursive) {
      final List<String> parts = path.split('/');
      String current = '';
      for (final String part in parts) {
        if (part.isEmpty) continue;
        current = current.isEmpty ? part : '$current/$part';
        _webDirectories.add(current);
      }
    }
    _webDirectories.add(path);
    return this;
  }

  Stream<FileSystemEntity> list(
      {bool recursive = false, bool followLinks = true}) async* {
    final String prefix = path == '.' ? '' : '$path/';
    for (final String key in _webFiles.keys.toList(growable: false)) {
      if (key.startsWith(prefix) &&
          (recursive || !key.substring(prefix.length).contains('/'))) {
        yield File(key);
      }
    }
    for (final String key in _webDirectories.toList(growable: false)) {
      if (key != path &&
          key.startsWith(prefix) &&
          (recursive || !key.substring(prefix.length).contains('/'))) {
        yield Directory(key);
      }
    }
  }

  List<FileSystemEntity> listSync({
    bool recursive = false,
    bool followLinks = true,
  }) =>
      <FileSystemEntity>[];

  Future<Directory> rename(String newPath) async =>
      Directory(_webPath(newPath));

  Directory renameSync(String newPath) => Directory(_webPath(newPath));

  @override
  Future<void> delete({bool recursive = false}) async {
    _webDirectories.remove(path);
    if (recursive) {
      final String prefix = path == '.' ? '' : '$path/';
      _webFiles.removeWhere((String key, _) => key.startsWith(prefix));
      _webDirectories.removeWhere((String key) => key.startsWith(prefix));
    }
  }

  @override
  void deleteSync({bool recursive = false}) {
    _webDirectories.remove(path);
    if (recursive) {
      final String prefix = path == '.' ? '' : '$path/';
      _webFiles.removeWhere((String key, _) => key.startsWith(prefix));
      _webDirectories.removeWhere((String key) => key.startsWith(prefix));
    }
  }
}

class RandomAccessFile {
  RandomAccessFile._(this._path, FileMode mode) {
    _bytes = _webFiles[_path] ?? Uint8List(0);
    if (mode == FileMode.append) {
      _position = _bytes.length;
    } else if (mode == FileMode.write || mode == FileMode.writeOnly) {
      _bytes = Uint8List(0);
      _position = 0;
    }
    _webFiles[_path] = _bytes;
    _webTouch(_path);
  }

  final String _path;
  late Uint8List _bytes;
  int _position = 0;

  Future<int> length() async => _bytes.length;

  int lengthSync() => _bytes.length;

  Future<int> position() async => _position;

  int positionSync() => _position;

  Future<RandomAccessFile> setPosition(int position) async {
    _position = position < 0 ? 0 : position;
    return this;
  }

  void setPositionSync(int position) => _position = position < 0 ? 0 : position;

  Future<void> writeFrom(List<int> buffer, [int start = 0, int? end]) async {
    writeFromSync(buffer, start, end);
  }

  void writeFromSync(List<int> buffer, [int start = 0, int? end]) {
    final int stop = end ?? buffer.length;
    final List<int> incoming = buffer.sublist(start, stop);
    _ensureCapacity(_position + incoming.length);
    for (final int byte in incoming) {
      _bytes[_position] = byte & 0xff;
      _position++;
    }
    _commit();
  }

  Future<void> writeByte(int byte) async => writeByteSync(byte);

  void writeByteSync(int byte) {
    _ensureCapacity(_position + 1);
    _bytes[_position] = byte & 0xff;
    _position++;
    _commit();
  }

  Future<void> writeString(String string, {Encoding encoding = utf8}) async =>
      writeFrom(encoding.encode(string));

  void writeStringSync(String string, {Encoding encoding = utf8}) =>
      writeFromSync(encoding.encode(string));

  Future<List<int>> read(int count) async => readSync(count);

  List<int> readSync(int count) {
    final int available = count < 0 ? 0 : count;
    final int start = _position > _bytes.length ? _bytes.length : _position;
    final int end =
        start + available > _bytes.length ? _bytes.length : start + available;
    final List<int> result = _bytes.sublist(start, end);
    _position = end;
    return result;
  }

  Future<void> truncate(int size) async => truncateSync(size);

  void truncateSync(int size) {
    final Uint8List resized = Uint8List(size < 0 ? 0 : size);
    final int copyLength = size < _bytes.length ? size : _bytes.length;
    if (copyLength > 0) {
      resized.setRange(0, copyLength, _bytes, 0);
    }
    _bytes = resized;
    if (_position > _bytes.length) _position = _bytes.length;
    _commit();
  }

  Future<void> flush() async {}

  void flushSync() {}

  Future<void> close() async {}

  void closeSync() {}

  void _ensureCapacity(int length) {
    if (length <= _bytes.length) return;
    final Uint8List resized = Uint8List(length);
    resized.setRange(0, _bytes.length, _bytes, 0);
    _bytes = resized;
  }

  void _commit() {
    _webFiles[_path] = _bytes;
    _webTouch(_path);
  }
}

abstract class Process {
  int get pid;
  Future<int> get exitCode;
  Stream<List<int>> get stdout;
  Stream<List<int>> get stderr;
  StreamSink<List<int>> get stdin;

  bool kill() => false;

  static Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
    bool includeParentEnvironment = true,
    bool runInShell = false,
    ProcessMode mode = ProcessMode.verbatim,
  }) async {
    throw const SocketException(
      'Child processes are not available in the browser.',
    );
  }
}

enum ProcessMode { verbatim, windows, posix }

class HttpHeaders {
  HttpHeaders._();

  final Map<String, String> _values = <String, String>{};

  String? value(String name) => _values[name.toLowerCase()];

  void set(String name, Object value) => _values[name.toLowerCase()] = '$value';

  void add(String name, Object value) => _values[name.toLowerCase()] = '$value';
}

class HttpClientRequest {
  HttpClientRequest._();

  final HttpHeaders headers = HttpHeaders._();
  Encoding encoding = utf8;

  void add(List<int> data) {}

  void write(Object? object) {}

  void closeNoFlush() {}

  void abort() {}

  Future<HttpClientResponse> close() async {
    throw const SocketException(
      'HTTP requests are not available in the browser build.',
    );
  }
}

class HttpClientResponse extends Stream<List<int>> {
  HttpClientResponse({this.statusCode = 0});

  final int statusCode;
  final HttpHeaders headers = HttpHeaders._();
  int? contentLength;
  bool get isRedirect => statusCode >= 300 && statusCode < 400;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) =>
      Stream<List<int>>.empty().listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      );
}

class HttpClient {
  Duration? connectionTimeout;
  bool autoCompress = false;
  bool persistentConnection = true;
  int maxConnectionsPerHost = 8;

  Future<HttpClientRequest> getUrl(Uri url) async => HttpClientRequest._();

  Future<HttpClientRequest> postUrl(Uri url) async => HttpClientRequest._();

  Future<HttpClientRequest> putUrl(Uri url) async => HttpClientRequest._();

  Future<HttpClientRequest> openUrl(String method, Uri url) async =>
      HttpClientRequest._();

  void close({bool force = false}) {}

  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) {}
}

abstract class HttpClientCredentials {}

class Socket {
  void destroy() {}

  static Future<Socket> connect(
    dynamic host,
    int port, {
    Duration? timeout,
  }) async {
    throw const SocketException(
      'Raw sockets are not available in the browser build.',
    );
  }
}

// ignore: constant_identifier_names
enum InternetAddressType { IPv4, IPv6 }

class InternetAddress {
  factory InternetAddress(String address) {
    final InternetAddress? parsed = tryParse(address);
    if (parsed == null) {
      throw const SocketException('Invalid IP address.');
    }
    return parsed;
  }

  InternetAddress._(this.address, this.type, this.rawAddress);

  final String address;
  final InternetAddressType type;
  final List<int> rawAddress;

  static InternetAddress? tryParse(String address) {
    try {
      return InternetAddress._(
        address,
        InternetAddressType.IPv4,
        Uri.parseIPv4Address(address),
      );
    } on FormatException {
      // Try IPv6 below.
    }
    try {
      return InternetAddress._(
        address,
        InternetAddressType.IPv6,
        Uri.parseIPv6Address(address),
      );
    } on FormatException {
      return null;
    }
  }

  @override
  String toString() => address;
}
