import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_snapshot.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

class OverviewGrid extends StatelessWidget {
  const OverviewGrid({super.key, required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final int? battery = snapshot.averageBatteryPercent;
    final List<_Metric> metrics = <_Metric>[
      _Metric(
        label: 'REGISTERED DEVICES',
        value: '${snapshot.registeredCount}',
        caption: snapshot.isDemo ? 'Sample device records' : 'Device records',
        icon: Icons.devices_other_outlined,
        color: AuraColors.primary,
        isDemo: snapshot.isDemo,
      ),
      _Metric(
        label: 'CONNECTED',
        value: '${snapshot.connectedCount}',
        caption: 'Live hardware links',
        icon: Icons.link_off_rounded,
        color: AuraColors.success,
      ),
      _Metric(
        label: 'BATTERY',
        value: battery == null ? '--' : '$battery%',
        caption: 'Reported by devices',
        icon: Icons.battery_unknown_outlined,
        color: AuraColors.warning,
      ),
      _Metric(
        label: 'AURA CORE',
        value: snapshot.coreLink == CoreLinkState.linked ? 'Online' : 'Offline',
        caption: 'Backend link not configured',
        icon: Icons.cloud_off_outlined,
        color: AuraColors.secondary,
      ),
      _Metric(
        label: 'NETWORK',
        value: snapshot.network == NetworkReadiness.configured
            ? 'Ready'
            : 'Not set',
        caption: 'Wi-Fi provisioning pending',
        icon: Icons.wifi_outlined,
        color: AuraColors.primary,
      ),
      _Metric(
        label: 'SECURITY',
        value: snapshot.security == SecurityReadiness.ready
            ? 'Protected'
            : 'PIN pending',
        caption: 'Workspace protection',
        icon: Icons.shield_outlined,
        color: AuraColors.warning,
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
          itemCount: metrics.length,
          itemBuilder: (BuildContext context, int index) {
            return _MetricCard(metric: metrics[index]);
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
    this.isDemo = false,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final Color color;
  final bool isDemo;
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: metric.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(metric.icon, size: 17, color: metric.color),
              ),
              const Spacer(),
              if (metric.isDemo)
                Text(
                  'DEMO',
                  style: text.labelSmall?.copyWith(color: AuraColors.warning),
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
    );
  }
}
