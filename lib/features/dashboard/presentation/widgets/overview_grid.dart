import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/features/dashboard/domain/system_metrics.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Host metrics and connection states are shown side by side but never mixed:
/// the Local API card describes telemetry transport, while AURA Core describes
/// actual hardware/backend linkage.
class OverviewGrid extends ConsumerWidget {
  const OverviewGrid({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final int pollSeconds =
        ref.watch(appSettingsProvider).pollingIntervalSeconds;
    final SystemMetrics metrics = snapshot.system;
    final List<_Metric> metricsToShow = <_Metric>[
      _Metric(
        label: 'HOST CPU',
        value: '${metrics.cpuPercent.toStringAsFixed(1)}%',
        caption: '${metrics.cpuCores} cores  -  ${metrics.cpuFrequencyMHz} MHz',
        icon: Icons.memory_outlined,
        color: AuraColors.primary,
      ),
      _Metric(
        label: 'HOST MEMORY',
        value: '${metrics.memoryPercent.toStringAsFixed(1)}%',
        caption: '${metrics.memoryUsedGiB.toStringAsFixed(1)} / '
            '${metrics.memoryTotalGiB.toStringAsFixed(1)} GB',
        icon: Icons.data_usage_outlined,
        color: AuraColors.secondary,
      ),
      _Metric(
        label: 'HOST DISK ${metrics.diskPath.trim()}',
        value: '${metrics.diskPercent.toStringAsFixed(1)}%',
        caption: '${metrics.diskFreeGiB.toStringAsFixed(1)} GB free',
        icon: Icons.storage_outlined,
        color: AuraColors.warning,
      ),
      _Metric(
        label: 'HOST NETWORK',
        value: '${metrics.activeInterfaceCount} links up',
        caption: 'Down ${formatRate(metrics.receivedPerSecond)}  -  '
            'Up ${formatRate(metrics.sentPerSecond)}',
        icon: Icons.network_check_outlined,
        color: AuraColors.success,
      ),
      _Metric(
        label: 'HOST UPTIME',
        value: formatUptime(metrics.uptimeSeconds),
        caption: 'Since ${formatEventTimestamp(metrics.bootTime)}',
        icon: Icons.schedule_outlined,
        color: AuraColors.primary,
      ),
      _Metric(
        label: 'LOCAL TELEMETRY API',
        value: snapshot.localApiOnline ? 'Online' : 'Unavailable',
        caption: snapshot.localApiOnline
            ? 'Windows host data  -  ${snapshot.apiUrl}'
            : 'Retrying every ${pollSeconds}s  -  ${snapshot.apiUrl}',
        icon: snapshot.localApiOnline
            ? Icons.cloud_done_outlined
            : Icons.cloud_off_outlined,
        color: snapshot.localApiOnline ? AuraColors.success : AuraColors.danger,
      ),
      _Metric(
        label: 'AURA CORE',
        value: snapshot.coreLink == CoreLinkState.notLinked
            ? 'Not linked'
            : snapshot.coreLink == CoreLinkState.linked
                ? 'Linked'
                : 'Degraded',
        caption: 'No AURA device backend connected',
        icon: Icons.link_off_outlined,
        color: AuraColors.textSecondary,
      ),
    ];

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 1180
            ? 3
            : constraints.maxWidth >= 560
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: AuraSpace.md,
            mainAxisSpacing: AuraSpace.md,
            mainAxisExtent: 152,
          ),
          itemCount: metricsToShow.length,
          itemBuilder: (BuildContext context, int index) {
            return _MetricCard(metric: metricsToShow[index]);
          },
        );
      },
    );
  }
}

class _Metric {
  const _Metric({
    required this.label,
    required this.value,
    required this.caption,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool isCore = metric.label == 'AURA CORE';

    return Semantics(
      container: true,
      label: '${metric.label}: ${metric.value}. ${metric.caption}',
      child: SurfaceCard(
        // Flat, mostly opaque bodies keep live numbers legible. Only the Core
        // status tile gets the stronger, elevated glass treatment.
        surface: isCore ? AuraGlassSurface.strong : AuraGlassSurface.card,
        borderColor:
            isCore ? AuraColors.secondary.withValues(alpha: 0.34) : null,
        padding: const EdgeInsets.all(AuraSpace.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                GlassContainer(
                  width: 34,
                  height: 34,
                  radius: 10,
                  blur: 8,
                  fill: 0.5,
                  showHighlight: false,
                  padding: EdgeInsets.zero,
                  borderColor: metric.color.withValues(alpha: 0.32),
                  child: Icon(metric.icon, size: 17, color: metric.color),
                ),
              ],
            ),
            const Spacer(),
            Text(metric.value, style: text.headlineMedium),
            const SizedBox(height: AuraSpace.xxs),
            Text(metric.label, style: text.labelMedium),
            const SizedBox(height: AuraSpace.xxs),
            Text(
              metric.caption,
              style: text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
