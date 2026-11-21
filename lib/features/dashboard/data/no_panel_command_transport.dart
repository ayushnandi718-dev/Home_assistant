import 'package:aura_hub/features/dashboard/domain/scene_action.dart';
import 'package:aura_hub/features/dashboard/domain/scene_command.dart';

/// Default transport until a real authenticated ESP32 command channel exists.
///
/// It intentionally never returns an acknowledgement: a pill must not claim a
/// scene ran when there is no hardware to run it.
class NoPanelCommandTransport implements SceneCommandTransport {
  const NoPanelCommandTransport();

  @override
  Future<SceneCommandResult> send(SceneAction action) async {
    return const SceneCommandResult.unavailable(
      'No ESP32 command transport is available yet.',
    );
  }
}
