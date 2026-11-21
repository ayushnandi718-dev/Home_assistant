/// No-op browser stand-in for the Windows job-object process guard.
class WindowsProcessGuard {
  const WindowsProcessGuard._();

  bool get isActive => false;

  static WindowsProcessGuard? attach(int pid) => null;

  void terminate() {}

  void dispose() {}
}
