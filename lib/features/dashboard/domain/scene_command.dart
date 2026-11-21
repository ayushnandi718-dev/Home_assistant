import 'package:aura_hub/features/dashboard/domain/scene_action.dart';

enum SceneCommandOutcome { acknowledged, failed, unavailable }

/// A command result is never "success" unless a real device acknowledged it.
class SceneCommandResult {
  const SceneCommandResult.acknowledged(this.message)
      : outcome = SceneCommandOutcome.acknowledged;

  const SceneCommandResult.failed(this.message)
      : outcome = SceneCommandOutcome.failed;

  const SceneCommandResult.unavailable(this.message)
      : outcome = SceneCommandOutcome.unavailable;

  final SceneCommandOutcome outcome;
  final String message;
}

/// Transport boundary for scene commands. The current app has no ESP32 link,
/// so the only implementation honestly reports that commands are unavailable.
abstract class SceneCommandTransport {
  const SceneCommandTransport();

  Future<SceneCommandResult> send(SceneAction action);
}
