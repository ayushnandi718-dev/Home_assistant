/// What can honestly be said about OS microphone permission right now.
enum MicrophonePermissionStatus {
  granted,
  denied,
  notDetermined,
  unknown,
}

/// What can honestly be said about an input device right now.
enum MicrophoneDeviceStatus { present, absent, unknown }

/// Read-only microphone capability snapshot.
///
/// `captureSupported` is the important field: when it is false, AURA has no
/// code path that opens an input device, regardless of the user's preference.
class MicrophoneStatus {
  const MicrophoneStatus({
    required this.permission,
    required this.device,
    required this.captureSupported,
    required this.message,
  });

  final MicrophonePermissionStatus permission;
  final MicrophoneDeviceStatus device;
  final bool captureSupported;
  final String message;

  String get permissionLabel => switch (permission) {
        MicrophonePermissionStatus.granted => 'Granted',
        MicrophonePermissionStatus.denied => 'Denied',
        MicrophonePermissionStatus.notDetermined => 'Not requested',
        MicrophonePermissionStatus.unknown => 'Not queryable in this build',
      };

  String get deviceLabel => switch (device) {
        MicrophoneDeviceStatus.present => 'Present',
        MicrophoneDeviceStatus.absent => 'Absent',
        MicrophoneDeviceStatus.unknown => 'Not queryable in this build',
      };
}

/// Boundary for a future permission-aware microphone implementation.
abstract class MicrophoneProbe {
  const MicrophoneProbe();

  Future<MicrophoneStatus> probe();
}

/// Honest Windows/desktop implementation for this build.
///
/// Flutter desktop has no microphone permission or device-enumeration API in
/// AURA Hub, and no capture plugin is installed. This probe therefore refuses
/// to guess: it reports unknown permission/device state and no capture support.
/// A platform-channel implementation can replace it without changing the UI.
class DesktopMicrophoneProbe extends MicrophoneProbe {
  const DesktopMicrophoneProbe();

  @override
  Future<MicrophoneStatus> probe() async => const MicrophoneStatus(
        permission: MicrophonePermissionStatus.unknown,
        device: MicrophoneDeviceStatus.unknown,
        captureSupported: false,
        message: 'This build has no microphone capture plugin. AURA cannot '
            'query OS permission or input devices and does not record audio. '
            'The switch below only saves a preference for a future voice '
            'pipeline.',
      );
}
