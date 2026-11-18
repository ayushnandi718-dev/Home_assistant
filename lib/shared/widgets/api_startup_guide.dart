import 'dart:async';

import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_log_store.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Compact service status card shown wherever the telemetry API matters.
///
/// AURA Hub owns the local process lifecycle; no terminal or PowerShell command
/// is required. Only stable status text is shown in the normal dashboard.
class ApiStartupGuide extends StatelessWidget {
  const ApiStartupGuide({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (BuildContext context, WidgetRef ref, Widget? _) {
        final TelemetryApiState state = ref.watch(telemetryApiStateProvider);
        final TextTheme text = Theme.of(context).textTheme;
        final Color tone = _tone(state.status);

        return SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(_icon(state.status), color: tone),
                  const SizedBox(width: AuraSpace.sm),
                  Expanded(
                    child: Text(
                      'Telemetry service · ${state.status.label}',
                      style: text.titleMedium,
                    ),
                  ),
                ],
              ),
              if (!compact) ...<Widget>[
                const SizedBox(height: AuraSpace.xs),
                Text(
                  state.message,
                  style: text.bodySmall,
                ),
                const SizedBox(height: AuraSpace.sm),
                Text(
                  'AURA Hub starts and monitors this local service silently. '
                  'No terminal window is used.',
                  style: text.bodySmall,
                ),
              ],
              const SizedBox(height: AuraSpace.sm),
              Wrap(
                spacing: AuraSpace.sm,
                runSpacing: AuraSpace.xs,
                children: <Widget>[
                  OutlinedButton.icon(
                    onPressed: () => unawaited(
                      ref.read(telemetryApiServiceProvider.notifier).restart(),
                    ),
                    icon: const Icon(Icons.restart_alt_rounded, size: 16),
                    label: const Text('Restart service'),
                  ),
                  TextButton.icon(
                    onPressed: () => _showLogs(context, ref),
                    icon: const Icon(Icons.article_outlined, size: 16),
                    label: const Text('Recent logs'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Color _tone(TelemetryApiStatus status) => switch (status) {
        TelemetryApiStatus.online => AuraColors.primary,
        TelemetryApiStatus.starting ||
        TelemetryApiStatus.reconnecting =>
          AuraColors.warning,
        TelemetryApiStatus.offline ||
        TelemetryApiStatus.startupFailed =>
          AuraColors.danger,
      };

  IconData _icon(TelemetryApiStatus status) => switch (status) {
        TelemetryApiStatus.online => Icons.cloud_done_outlined,
        TelemetryApiStatus.starting ||
        TelemetryApiStatus.reconnecting =>
          Icons.sync_rounded,
        TelemetryApiStatus.offline ||
        TelemetryApiStatus.startupFailed =>
          Icons.cloud_off_outlined,
      };

  Future<void> _showLogs(BuildContext context, WidgetRef ref) async {
    final TelemetryApiLogStore store = ref.read(telemetryApiLogStoreProvider);
    final List<String> lines = await store.readRecent(limit: 60);
    if (!context.mounted) return;
    await showGlassDialog<void>(
      context: context,
      width: 680,
      child: _RecentLogsDialog(lines: lines),
    );
  }
}

class _RecentLogsDialog extends StatelessWidget {
  const _RecentLogsDialog({required this.lines});

  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Recent telemetry service logs', style: text.headlineSmall),
        const SizedBox(height: AuraSpace.sm),
        Text(
          'Sanitized startup, health and shutdown events only.',
          style: text.bodySmall,
        ),
        const SizedBox(height: AuraSpace.md),
        SizedBox(
          height: 360,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AuraColors.backgroundDeep,
              borderRadius: BorderRadius.circular(AuraRadius.control),
              border: Border.all(color: AuraColors.border),
            ),
            child: lines.isEmpty
                ? const Center(child: Text('No service logs yet.'))
                : ListView.builder(
                    itemCount: lines.length,
                    itemBuilder: (BuildContext context, int index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AuraSpace.sm,
                        vertical: AuraSpace.xxs,
                      ),
                      child: SelectableText(
                        lines[index],
                        style: text.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        const SizedBox(height: AuraSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      ],
    );
  }
}
