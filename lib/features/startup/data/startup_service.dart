/// Outcome of applying a Windows startup preference.
class StartupApplyResult {
  const StartupApplyResult({required this.ok, this.error});

  final bool ok;
  final String? error;
}

/// Current state of the AURA startup registration.
class StartupRegistration {
  const StartupRegistration({
    required this.supported,
    this.registered = false,
    this.command,
    this.error,
  });

  final bool supported;
  final bool registered;
  final String? command;
  final String? error;
}

/// Platform-neutral boundary so non-Windows/test callers get a graceful no-op.
abstract interface class StartupService {
  bool get supported;

  /// Creates or removes exactly one CurrentUser Run entry. Never stores a PIN
  /// or any authentication secret in the command line.
  Future<StartupApplyResult> apply({
    required bool enabled,
    required bool startMinimized,
  });

  /// Reads the current registration for diagnostics/user explanation.
  Future<StartupRegistration> read();

  /// Applies the persisted "start minimized" preference on launch.
  void minimizeIfRequested(bool startMinimized);
}

/// No-op implementation used off Windows and in tests.
class UnsupportedStartupService implements StartupService {
  const UnsupportedStartupService();

  @override
  bool get supported => false;

  @override
  Future<StartupApplyResult> apply({
    required bool enabled,
    required bool startMinimized,
  }) async =>
      const StartupApplyResult(
          ok: false, error: 'Not available on this platform.');

  @override
  Future<StartupRegistration> read() async =>
      const StartupRegistration(supported: false);

  @override
  void minimizeIfRequested(bool startMinimized) {}
}
