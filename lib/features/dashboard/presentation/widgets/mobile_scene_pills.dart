import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/scene_action.dart';
import 'package:aura_hub/features/dashboard/presentation/scene_actions_provider.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compact scene row. Panel-dependent actions are disabled until a real link
/// reports connected, and their state never advances without an acknowledgement.
class MobileScenePills extends ConsumerWidget {
  const MobileScenePills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DeviceLinkState link = ref.watch(deviceLinkProvider);
    final bool canControlPanel = link.isConnected;
    final SceneActionStates states = ref.watch(sceneActionsProvider);

    final String? statusMessage = states.values
        .where(
          (SceneActionState state) =>
              state.status == SceneActionStatus.pending ||
              state.status == SceneActionStatus.failed ||
              state.status == SceneActionStatus.success,
        )
        .map((SceneActionState state) => state.message)
        .whereType<String>()
        .toList()
        .fold<String?>(
          null,
          (String? previous, String message) => previous ?? message,
        );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double pillWidth = (constraints.maxWidth - AuraSpace.sm) / 2;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Wrap(
              spacing: AuraSpace.sm,
              runSpacing: AuraSpace.sm,
              children: <Widget>[
                for (final SceneAction action in SceneAction.values)
                  SizedBox(
                    key: ValueKey<String>('scene-pill-${action.name}'),
                    width: pillWidth > 140 ? pillWidth : constraints.maxWidth,
                    child: _ScenePill(
                      action: action,
                      enabled: canControlPanel,
                      state: states[action] ?? const SceneActionState(),
                      onTap: canControlPanel
                          ? () =>
                              ref.read(sceneActionsProvider.notifier).execute(
                                    action,
                                    canControlPanel: true,
                                  )
                          : null,
                    ),
                  ),
              ],
            ),
            if (statusMessage != null) ...<Widget>[
              const SizedBox(height: AuraSpace.sm),
              Text(
                statusMessage,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AuraColors.textSecondary,
                    ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _ScenePill extends StatelessWidget {
  const _ScenePill({
    required this.action,
    required this.enabled,
    required this.state,
    required this.onTap,
  });

  final SceneAction action;
  final bool enabled;
  final SceneActionState state;
  final VoidCallback? onTap;

  IconData get _icon => switch (action) {
        SceneAction.nightMode => Icons.nightlight_round,
        SceneAction.nextWallpaper => Icons.wallpaper_rounded,
        SceneAction.syncNow => Icons.sync_rounded,
        SceneAction.restartPanel => Icons.restart_alt_rounded,
      };

  Widget get _trailing => switch (state.status) {
        SceneActionStatus.pending => SizedBox.square(
            dimension: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AuraColors.primary),
            ),
          ),
        SceneActionStatus.success => const Icon(
            Icons.check_circle_rounded,
            size: 19,
            color: AuraColors.success,
          ),
        SceneActionStatus.failed => const Icon(
            Icons.error_outline_rounded,
            size: 19,
            color: AuraColors.warning,
          ),
        SceneActionStatus.idle => const Icon(
            Icons.play_arrow_rounded,
            size: 19,
            color: AuraColors.textSecondary,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final BorderRadius radius = BorderRadius.circular(20);
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: Material(
        color: Colors.transparent,
        child: Tooltip(
          message: state.message ?? '',
          excludeFromSemantics: state.message == null,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AuraSpace.sm,
                vertical: 14,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: radius,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.08),
                ),
              ),
              child: Row(
                children: <Widget>[
                  Icon(_icon, size: 19, color: AuraColors.textPrimary),
                  const SizedBox(width: AuraSpace.xs),
                  Expanded(
                    child: Text(
                      action.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(width: AuraSpace.xxs),
                  _trailing,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
