import 'package:aura_hub/features/dashboard/data/no_panel_command_transport.dart';
import 'package:aura_hub/features/dashboard/domain/scene_action.dart';
import 'package:aura_hub/features/dashboard/domain/scene_command.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final Provider<SceneCommandTransport> sceneCommandTransportProvider =
    Provider<SceneCommandTransport>((Ref ref) {
  return const NoPanelCommandTransport();
});

enum SceneActionStatus { idle, pending, success, failed }

class SceneActionState {
  const SceneActionState({
    this.status = SceneActionStatus.idle,
    this.message,
  });

  final SceneActionStatus status;
  final String? message;

  bool get isPending => status == SceneActionStatus.pending;
}

typedef SceneActionStates = Map<SceneAction, SceneActionState>;

SceneActionStates _initialStates() => <SceneAction, SceneActionState>{
      for (final SceneAction action in SceneAction.values)
        action: const SceneActionState(),
    };

/// Prevents duplicate execution and only records a success after an explicit
/// acknowledgement from the command transport.
class SceneActionController extends StateNotifier<SceneActionStates> {
  SceneActionController(this._transport) : super(_initialStates());

  final SceneCommandTransport _transport;
  bool _disposed = false;

  Future<void> execute(
    SceneAction action, {
    required bool canControlPanel,
  }) async {
    if (_disposed || (state[action]?.isPending ?? false)) return;

    if (!canControlPanel) {
      _set(
        action,
        SceneActionStatus.failed,
        'Pair and connect an AURA panel first.',
      );
      return;
    }

    _set(
      action,
      SceneActionStatus.pending,
      'Waiting for panel acknowledgement…',
    );

    try {
      final SceneCommandResult result = await _transport.send(action);
      if (_disposed) return;
      switch (result.outcome) {
        case SceneCommandOutcome.acknowledged:
          _set(action, SceneActionStatus.success, result.message);
        case SceneCommandOutcome.failed:
        case SceneCommandOutcome.unavailable:
          _set(action, SceneActionStatus.failed, result.message);
      }
    } on Object catch (error) {
      if (_disposed) return;
      _set(action, SceneActionStatus.failed, 'Command failed: $error');
    }
  }

  void clear(SceneAction action) => _set(action, SceneActionStatus.idle, null);

  void _set(SceneAction action, SceneActionStatus status, String? message) {
    if (_disposed) return;
    state = <SceneAction, SceneActionState>{
      ...state,
      action: SceneActionState(status: status, message: message),
    };
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final StateNotifierProvider<SceneActionController, SceneActionStates>
    sceneActionsProvider =
    StateNotifierProvider<SceneActionController, SceneActionStates>((Ref ref) {
  return SceneActionController(ref.read(sceneCommandTransportProvider));
});
