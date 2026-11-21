import 'dart:ffi';
import 'package:aura_hub/core/platform/io_compat.dart';

import 'package:ffi/ffi.dart';

typedef _CreateJobObjectWNative = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _CreateJobObjectWDart = Pointer<Void> Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _SetInformationJobObjectNative = Int32 Function(
  Pointer<Void>,
  Int32,
  Pointer<Void>,
  Uint32,
);
typedef _SetInformationJobObjectDart = int Function(
  Pointer<Void>,
  int,
  Pointer<Void>,
  int,
);
typedef _AssignProcessToJobObjectNative = Int32 Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _AssignProcessToJobObjectDart = int Function(
  Pointer<Void>,
  Pointer<Void>,
);
typedef _OpenProcessNative = Pointer<Void> Function(
  Uint32,
  Int32,
  Uint32,
);
typedef _OpenProcessDart = Pointer<Void> Function(
  int,
  int,
  int,
);
typedef _CloseHandleNative = Int32 Function(Pointer<Void>);
typedef _CloseHandleDart = int Function(Pointer<Void>);
typedef _TerminateJobObjectNative = Int32 Function(Pointer<Void>, Uint32);
typedef _TerminateJobObjectDart = int Function(Pointer<Void>, int);

/// Associates a child process started by AURA Hub with a private Windows job.
///
/// The job uses `JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE`, so the OS reaps the child
/// even if AURA Hub exits unexpectedly. Only processes explicitly assigned by
/// this class can ever be terminated; port ownership is never used to identify
/// a process to kill.
class WindowsProcessGuard {
  WindowsProcessGuard._(this._job, this._assigned);

  static const int _jobObjectExtendedLimitInformation = 9;
  static const int _jobObjectLimitKillOnJobClose = 0x00002000;
  static const int _processTerminate = 0x0001;
  static const int _processSetQuota = 0x0100;

  static bool _bound = false;
  static _CreateJobObjectWDart? _createJobObject;
  static _SetInformationJobObjectDart? _setInformationJobObject;
  static _AssignProcessToJobObjectDart? _assignProcessToJobObject;
  static _OpenProcessDart? _openProcess;
  static _CloseHandleDart? _closeHandle;
  static _TerminateJobObjectDart? _terminateJobObject;

  final Pointer<Void>? _job;
  final bool _assigned;

  bool get isActive => Platform.isWindows && _job != null && _assigned;

  /// Returns `null` when the platform is not Windows or job assignment fails.
  /// Failure is non-fatal: the caller still tracks the Dart [Process] directly.
  static WindowsProcessGuard? attach(int pid) {
    if (!Platform.isWindows) return null;
    if (!_bind()) return null;

    final Pointer<Void> job = _createJobObject!(nullptr, nullptr);
    if (job == nullptr) return null;

    final int pointerSize = sizeOf<IntPtr>();
    final int basicLimitSize = pointerSize == 8 ? 64 : 48;
    // JOBOBJECT_EXTENDED_LIMIT_INFORMATION = basic limits + IO_COUNTERS (48)
    // + four SIZE_T memory limits. Windows rejects a mismatched cb buffer.
    final int infoSize = basicLimitSize + 48 + (4 * pointerSize);
    final Pointer<Uint8> info = malloc.allocate<Uint8>(infoSize);
    try {
      info.asTypedList(infoSize).fillRange(0, infoSize, 0);
      // LimitFlags is the third field of JOBOBJECT_BASIC_LIMIT_INFORMATION and
      // is at byte offset 16 on both x86 and x64 Windows. Uint32 elements are
      // 4 bytes, so this is element 4.
      info.cast<Uint32>().elementAt(4).value = _jobObjectLimitKillOnJobClose;
      if (_setInformationJobObject!(
            job,
            _jobObjectExtendedLimitInformation,
            info.cast<Void>(),
            infoSize,
          ) ==
          0) {
        _closeHandle!(job);
        return null;
      }

      final Pointer<Void> processHandle = _openProcess!(
        _processTerminate | _processSetQuota,
        0,
        pid,
      );
      if (processHandle == nullptr) {
        _closeHandle!(job);
        return null;
      }
      try {
        final int assigned = _assignProcessToJobObject!(job, processHandle);
        if (assigned == 0) {
          _closeHandle!(job);
          return null;
        }
      } finally {
        _closeHandle!(processHandle);
      }
      return WindowsProcessGuard._(job, true);
    } finally {
      malloc.free(info);
    }
  }

  /// Terminates only this app-managed job, as a last resort after a graceful
  /// shutdown request has been given time to complete.
  void terminate() {
    final Pointer<Void>? job = _job;
    if (job != null && _assigned) {
      _terminateJobObject?.call(job, 0);
    }
  }

  void dispose() {
    final Pointer<Void>? job = _job;
    if (job != null) _closeHandle?.call(job);
  }

  static bool _bind() {
    if (_bound) return _createJobObject != null;
    _bound = true;
    try {
      final DynamicLibrary kernel32 = DynamicLibrary.open('kernel32.dll');
      _createJobObject = kernel32.lookupFunction<_CreateJobObjectWNative,
          _CreateJobObjectWDart>('CreateJobObjectW');
      _setInformationJobObject = kernel32.lookupFunction<
          _SetInformationJobObjectNative,
          _SetInformationJobObjectDart>('SetInformationJobObject');
      _assignProcessToJobObject = kernel32.lookupFunction<
          _AssignProcessToJobObjectNative,
          _AssignProcessToJobObjectDart>('AssignProcessToJobObject');
      _openProcess = kernel32
          .lookupFunction<_OpenProcessNative, _OpenProcessDart>('OpenProcess');
      _closeHandle = kernel32
          .lookupFunction<_CloseHandleNative, _CloseHandleDart>('CloseHandle');
      _terminateJobObject = kernel32.lookupFunction<_TerminateJobObjectNative,
          _TerminateJobObjectDart>('TerminateJobObject');
    } on Object {
      return false;
    }
    return true;
  }
}
