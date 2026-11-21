import 'package:aura_hub/features/startup/data/startup_service.dart';

class WindowsStartupException implements Exception {
  const WindowsStartupException(this.status);

  final int status;

  @override
  String toString() => 'Windows registry call failed (code $status).';
}

class WindowsStartupService implements StartupService {
  const WindowsStartupService();

  static const String valueName = 'AURA Hub';

  static String buildCommand(
    String executable, {
    required bool startMinimized,
  }) {
    final String quoted =
        executable.contains(' ') ? '"$executable"' : executable;
    return startMinimized ? '$quoted --start-minimized' : quoted;
  }

  @override
  bool get supported => false;

  String commandFor({required bool startMinimized}) =>
      buildCommand('aura_hub/web', startMinimized: startMinimized);

  @override
  Future<StartupApplyResult> apply({
    required bool enabled,
    required bool startMinimized,
  }) async =>
      const StartupApplyResult(
        ok: false,
        error: 'Windows startup integration is unavailable in the browser.',
      );

  @override
  Future<StartupRegistration> read() async =>
      const StartupRegistration(supported: false);

  @override
  void minimizeIfRequested(bool startMinimized) {}
}
