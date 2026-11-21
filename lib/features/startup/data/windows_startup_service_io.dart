import 'dart:ffi';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:aura_hub/features/startup/data/startup_service.dart';
import 'package:ffi/ffi.dart';

// Win32 registry constants (winreg.h / winnt.h).
const int _hkeyCurrentUser =
    -2147483647; // (HKEY)(LONG)0x80000001, sign-extended
const int _keyQueryValue = 0x0001;
const int _keySetValue = 0x0002;
const int _regSz = 1;
const int _errorSuccess = 0;
const int _errorFileNotFound = 2;

// Native signatures (Win32 ABI).
typedef _RegOpenKeyExWNative = Uint32 Function(
  IntPtr,
  Pointer<Uint16>,
  Uint32,
  Uint32,
  Pointer<Pointer<Void>>,
);
typedef _RegSetValueExWNative = Uint32 Function(
  IntPtr,
  Pointer<Uint16>,
  Uint32,
  Uint32,
  Pointer<Uint8>,
  Uint32,
);
typedef _RegDeleteValueWNative = Uint32 Function(IntPtr, Pointer<Uint16>);
typedef _RegQueryValueExWNative = Uint32 Function(
  IntPtr,
  Pointer<Uint16>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint8>,
  Pointer<Uint32>,
);
typedef _RegCloseKeyNative = Uint32 Function(IntPtr);

// Dart-facing signatures (plain int for native integers/pointers).
typedef _RegOpenKeyExW = int Function(
  int,
  Pointer<Uint16>,
  int,
  int,
  Pointer<Pointer<Void>>,
);
typedef _RegSetValueExW = int Function(
  int,
  Pointer<Uint16>,
  int,
  int,
  Pointer<Uint8>,
  int,
);
typedef _RegDeleteValueW = int Function(int, Pointer<Uint16>);
typedef _RegQueryValueExW = int Function(
  int,
  Pointer<Uint16>,
  Pointer<Uint32>,
  Pointer<Uint32>,
  Pointer<Uint8>,
  Pointer<Uint32>,
);
typedef _RegCloseKey = int Function(int);

final class _Registry {
  _Registry()
      : _advapi32 = DynamicLibrary.open('advapi32.dll'),
        _user32 = DynamicLibrary.open('user32.dll') {
    _openKey = _advapi32
        .lookupFunction<_RegOpenKeyExWNative, _RegOpenKeyExW>('RegOpenKeyExW');
    _setValue =
        _advapi32.lookupFunction<_RegSetValueExWNative, _RegSetValueExW>(
            'RegSetValueExW');
    _deleteValue =
        _advapi32.lookupFunction<_RegDeleteValueWNative, _RegDeleteValueW>(
            'RegDeleteValueW');
    _queryValue =
        _advapi32.lookupFunction<_RegQueryValueExWNative, _RegQueryValueExW>(
            'RegQueryValueExW');
    _closeKey = _advapi32
        .lookupFunction<_RegCloseKeyNative, _RegCloseKey>('RegCloseKey');
    _getActiveWindow = _user32.lookupFunction<Pointer<Void> Function(),
        Pointer<Void> Function()>('GetActiveWindow');
    _showWindow = _user32.lookupFunction<Int32 Function(Pointer<Void>, Int32),
        int Function(Pointer<Void>, int)>('ShowWindow');
  }

  final DynamicLibrary _advapi32;
  final DynamicLibrary _user32;
  late final _RegOpenKeyExW _openKey;
  late final _RegSetValueExW _setValue;
  late final _RegDeleteValueW _deleteValue;
  late final _RegQueryValueExW _queryValue;
  late final _RegCloseKey _closeKey;
  late final Pointer<Void> Function() _getActiveWindow;
  late final int Function(Pointer<Void>, int) _showWindow;

  int openRunKey() {
    final Pointer<Pointer<Void>> result = calloc<Pointer<Void>>();
    try {
      final Pointer<Uint16> subKey = _wide(
        r'Software\Microsoft\Windows\CurrentVersion\Run',
      );
      try {
        final int status = _openKey(
          _hkeyCurrentUser,
          subKey,
          0,
          _keyQueryValue | _keySetValue,
          result,
        );
        return status == _errorSuccess ? result.value.address : 0;
      } finally {
        calloc.free(subKey);
      }
    } finally {
      calloc.free(result);
    }
  }

  int writeValue(int key, String name, String value) {
    final Pointer<Uint16> wideName = _wide(name);
    final Pointer<Uint16> wideValue = _wide(value);
    try {
      // _wide allocates value.length + 1 code units (the last is NUL); REG_SZ
      // includes that terminator in cbData.
      final int byteCount = (value.length + 1) * 2;
      return _setValue(
        key,
        wideName,
        0,
        _regSz,
        wideValue.cast<Uint8>(),
        byteCount,
      );
    } finally {
      calloc.free(wideName);
      calloc.free(wideValue);
    }
  }

  int deleteValue(int key, String name) {
    final Pointer<Uint16> wideName = _wide(name);
    try {
      return _deleteValue(key, wideName);
    } finally {
      calloc.free(wideName);
    }
  }

  String? readValue(int key, String name) {
    final Pointer<Uint16> wideName = _wide(name);
    final Pointer<Uint32> type = calloc<Uint32>();
    final Pointer<Uint32> length = calloc<Uint32>();
    try {
      int status = _queryValue(key, wideName, nullptr, type, nullptr, length);
      if (status == _errorFileNotFound) return null;
      if (status != _errorSuccess) throw WindowsStartupException(status);
      final int units = length.value ~/ 2;
      if (units <= 0) return '';
      final Pointer<Uint16> buffer = calloc<Uint16>(units + 1);
      try {
        status = _queryValue(
          key,
          wideName,
          nullptr,
          type,
          buffer.cast<Uint8>(),
          length,
        );
        if (status != _errorSuccess) throw WindowsStartupException(status);
        final StringBuffer result = StringBuffer();
        for (int i = 0; i < units; i++) {
          final int unit = buffer[i];
          if (unit == 0) break;
          result.writeCharCode(unit);
        }
        return result.toString();
      } finally {
        calloc.free(buffer);
      }
    } finally {
      calloc.free(wideName);
      calloc.free(type);
      calloc.free(length);
    }
  }

  void closeKey(int address) {
    if (address != 0) _closeKey(address);
  }

  /// Minimises the active window of this process. `SW_MINIMIZE = 6`.
  void minimizeActiveWindow() {
    final Pointer<Void> window = _getActiveWindow();
    if (window != nullptr) _showWindow(window, 6);
  }

  /// UTF-16LE, NUL-terminated, allocated with calloc.
  Pointer<Uint16> _wide(String value) {
    final Pointer<Uint16> buffer = calloc<Uint16>(value.length + 1);
    for (int i = 0; i < value.length; i++) {
      buffer[i] = value.codeUnitAt(i);
    }
    buffer[value.length] = 0;
    return buffer;
  }
}

class WindowsStartupException implements Exception {
  const WindowsStartupException(this.status);

  final int status;

  @override
  String toString() => 'Windows registry call failed (code $status).';
}

/// Windows CurrentUser Run-key implementation.
///
/// Uses only HKCU - no elevated tasks, no Windows service. A single fixed value
/// name guarantees there is never a duplicate entry, and toggling off removes
/// that value entirely (fully reversible).
class WindowsStartupService implements StartupService {
  WindowsStartupService() : _registry = _Registry();

  static const String valueName = 'AURA Hub';

  final _Registry _registry;

  @override
  bool get supported => Platform.isWindows;

  /// Pure command builder, also used by tests: the startup value contains only
  /// the quoted executable path and an optional benign display flag. No PIN,
  /// path to private data or authentication secret is ever written here.
  static String buildCommand(
    String executable, {
    required bool startMinimized,
  }) {
    final String quoted =
        executable.contains(' ') ? '"$executable"' : executable;
    return startMinimized ? '$quoted --start-minimized' : quoted;
  }

  String commandFor({required bool startMinimized}) =>
      buildCommand(Platform.resolvedExecutable, startMinimized: startMinimized);

  @override
  Future<StartupApplyResult> apply({
    required bool enabled,
    required bool startMinimized,
  }) async {
    if (!Platform.isWindows) {
      return const StartupApplyResult(
        ok: false,
        error: 'Windows startup is only available on Windows.',
      );
    }
    final int key = _registry.openRunKey();
    if (key == 0) {
      return const StartupApplyResult(
        ok: false,
        error: 'Could not open the per-user startup settings. '
            'Check your Windows account permissions.',
      );
    }
    try {
      if (!enabled) {
        final int status = _registry.deleteValue(key, valueName);
        if (status == _errorSuccess || status == _errorFileNotFound) {
          return const StartupApplyResult(ok: true);
        }
        return StartupApplyResult(
          ok: false,
          error: 'Could not remove the startup entry (code $status).',
        );
      }
      final int status = _registry.writeValue(
        key,
        valueName,
        commandFor(startMinimized: startMinimized),
      );
      if (status == _errorSuccess) return const StartupApplyResult(ok: true);
      return StartupApplyResult(
        ok: false,
        error: 'Could not create the startup entry (code $status).',
      );
    } on Object catch (error) {
      return StartupApplyResult(
        ok: false,
        error: 'Windows startup integration failed: $error',
      );
    } finally {
      _registry.closeKey(key);
    }
  }

  @override
  Future<StartupRegistration> read() async {
    if (!Platform.isWindows) {
      return const StartupRegistration(supported: false);
    }
    final int key = _registry.openRunKey();
    if (key == 0) {
      return const StartupRegistration(
        supported: true,
        error: 'Could not read the per-user startup settings.',
      );
    }
    try {
      final String? command = _registry.readValue(key, valueName);
      return StartupRegistration(
        supported: true,
        registered: command != null,
        command: command,
      );
    } on Object catch (error) {
      return StartupRegistration(supported: true, error: '$error');
    } finally {
      _registry.closeKey(key);
    }
  }

  @override
  void minimizeIfRequested(bool startMinimized) {
    if (!Platform.isWindows || !startMinimized) return;
    _registry.minimizeActiveWindow();
  }
}
