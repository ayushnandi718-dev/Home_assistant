import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/diagnostics/domain/sampler_health.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

/// Explicit, independent status rows. A healthy HTTP API never implies healthy
/// background sampling or a paired AURA device.
class SourceHealthCard extends StatelessWidget {
  const SourceHealthCard({
    super.key,
    required this.connection,
    required this.sampler,
    required this.coreLink,
    required this.deviceCount,
    this.apiHealth,
  });

  final DashboardConnectionStatus connection;
  final SamplerHealth? sampler;
  final CoreLinkState coreLink;
  final int deviceCount;
  final ApiHealth? apiHealth;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    final String apiLabel = !connection.active
        ? 'Idle'
        : connection.stale
            ? 'Reconnecting'
            : connection.localApiOnline
                ? 'Online'
                : 'Offline';
    final Color apiColor = connection.stale || !connection.localApiOnline
        ? AuraColors.warning
        : AuraColors.success;

    final SamplerReadiness samplerStatus =
        sampler?.status ?? SamplerReadiness.initializing;
    final Color samplerColor = switch (samplerStatus) {
      SamplerReadiness.ready => AuraColors.success,
      SamplerReadiness.degraded => AuraColors.danger,
      SamplerReadiness.initializing => AuraColors.warning,
    };

    final DateTime? lastSample =
        sampler?.lastSuccessAt ?? connection.lastSuccess;
    final String lastSampleLabel = lastSample == null
        ? 'None yet'
        : lastSample.toLocal().toString().substring(0, 19);

    final String hardwareLabel =
        deviceCount == 0 && coreLink == CoreLinkState.notLinked
            ? 'Not paired'
            : coreLink == CoreLinkState.linked
                ? 'Connected'
                : 'Disconnected';

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.health_and_safety_outlined, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Text('Source health', style: text.titleLarge),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          _HealthRow(label: 'HTTP API', value: apiLabel, color: apiColor),
          _HealthRow(
            label: 'Telemetry sampler',
            value: sampler?.label ?? 'Unavailable',
            color: samplerColor,
          ),
          _HealthRow(label: 'Last successful sample', value: lastSampleLabel),
          _HealthRow(
            label: 'AURA hardware',
            value: hardwareLabel,
            color: hardwareLabel == 'Connected'
                ? AuraColors.success
                : AuraColors.textSecondary,
          ),
          if (apiHealth != null && apiHealth!.version != null) ...<Widget>[
            const SizedBox(height: AuraSpace.xs),
            Text(
              'API version ${apiHealth!.version} '
              '· last check ${apiHealth!.responseTime.inMilliseconds} ms',
              style: text.bodySmall,
            ),
          ],
          const SizedBox(height: AuraSpace.md),
          Text(
            'HTTP availability, background sampler health and physical AURA '
            'connection are tracked independently.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xxs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodyMedium)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
