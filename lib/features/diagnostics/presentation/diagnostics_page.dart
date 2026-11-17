import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/core/utilities/local_paths.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_connection_status.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_providers.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real diagnostics from the running app: recent local API requests, live
/// connection state and an exportable snapshot. No invented log entries.
class DiagnosticsPage extends ConsumerWidget {
  const DiagnosticsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<ApiRequestRecord> records = ref.watch(diagnosticsProvider);
    final DashboardConnectionStatus connection =
        ref.watch(dashboardStatusProvider);
    final TextTheme text = Theme.of(context).textTheme;

    final int successCount =
        records.where((ApiRequestRecord r) => r.succeeded).length;
    final double successRate =
        records.isEmpty ? 0 : (successCount * 100) / records.length;
    final Iterable<ApiRequestRecord> successes =
        records.where((ApiRequestRecord r) => r.succeeded);
    final int totalMs = successes.fold<int>(
      0,
      (int sum, ApiRequestRecord r) => sum + r.duration.inMilliseconds,
    );
    final int averageMs =
        successes.isEmpty ? 0 : (totalMs / successes.length).round();

    return AuraScrollArea(
      padding: EdgeInsets.fromLTRB(
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.lg,
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              PageHeader(
                eyebrow: 'System',
                title: 'Diagnostics & Logs',
                description:
                    'Live health of the local Windows telemetry API and the '
                    'requests this app has made to it.',
                icon: Icons.monitor_heart_outlined,
                trailing:
                    _ExportButton(records: records, connection: connection),
              ),
              const SizedBox(height: AuraSpace.lg),
              InfoBanner(
                title: connection.label,
                message: connection.lastSuccess == null
                    ? 'No successful telemetry snapshot has been received yet.'
                    : 'Last successful update: '
                        '${connection.lastSuccess!.toLocal().toString().substring(0, 19)}. '
                        '${connection.error == null ? 'The local API is healthy.' : 'Most recent error: ${connection.error}'}',
                icon: connection.stale
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_done_outlined,
                tone: connection.stale || !connection.localApiOnline
                    ? AuraBannerTone.warning
                    : AuraBannerTone.info,
              ),
              const SizedBox(height: AuraSpace.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final int columns = constraints.maxWidth >= 900 ? 4 : 2;
                  return GridView.count(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisCount: columns,
                    mainAxisExtent: 116,
                    crossAxisSpacing: AuraSpace.md,
                    mainAxisSpacing: AuraSpace.md,
                    children: <Widget>[
                      _StatCard(
                        label: 'REQUESTS',
                        value: '${records.length}',
                        caption: 'Last 100 recorded',
                        icon: Icons.http_rounded,
                        color: AuraColors.primary,
                      ),
                      _StatCard(
                        label: 'SUCCESS RATE',
                        value: '${successRate.toStringAsFixed(0)}%',
                        caption: '$successCount of ${records.length}',
                        icon: Icons.check_circle_outline_rounded,
                        color: AuraColors.success,
                      ),
                      _StatCard(
                        label: 'AVG LATENCY',
                        value: '$averageMs ms',
                        caption: 'Successful requests',
                        icon: Icons.speed_outlined,
                        color: AuraColors.secondary,
                      ),
                      _StatCard(
                        label: 'API STATE',
                        value: connection.stale
                            ? 'Reconnecting'
                            : connection.localApiOnline
                                ? 'Online'
                                : 'Offline',
                        caption: connection.label,
                        icon: Icons.network_check_outlined,
                        color: connection.localApiOnline
                            ? AuraColors.success
                            : AuraColors.warning,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text('Recent requests', style: text.titleLarge),
                        const Spacer(),
                        if (records.isNotEmpty)
                          TextButton.icon(
                            onPressed: () =>
                                ref.read(diagnosticsProvider.notifier).clear(),
                            icon: const Icon(Icons.clear_all_rounded, size: 16),
                            label: const Text('Clear'),
                          ),
                      ],
                    ),
                    const SizedBox(height: AuraSpace.md),
                    if (records.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: AuraSpace.xl,
                        ),
                        child: Center(
                          child: Text(
                            'No requests recorded yet. Open the dashboard to '
                            'start live telemetry.',
                            style: text.bodyMedium,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: records.length,
                        separatorBuilder: (BuildContext context, int index) =>
                            const Divider(height: 1),
                        itemBuilder: (BuildContext context, int index) {
                          final ApiRequestRecord record = records[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(
                              record.succeeded
                                  ? Icons.check_circle_outline_rounded
                                  : Icons.error_outline_rounded,
                              color: record.succeeded
                                  ? AuraColors.success
                                  : AuraColors.danger,
                              size: 18,
                            ),
                            title: Text(
                              '${record.path}  -  ${record.succeeded ? 'HTTP ${record.statusCode}' : 'Failed'}',
                              style: text.bodyMedium,
                            ),
                            subtitle: Text(
                              record.error ??
                                  '${record.duration.inMilliseconds} ms  -  '
                                      '${record.startedAt.toLocal().toString().substring(11, 19)}',
                              style: text.bodySmall,
                            ),
                            trailing: Text(
                              '${record.duration.inMilliseconds} ms',
                              style: text.labelMedium,
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
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
              Icon(icon, size: 16, color: color),
              const SizedBox(width: AuraSpace.xs),
              Text(label, style: text.labelMedium),
            ],
          ),
          const Spacer(),
          Text(value, style: text.headlineSmall),
          const SizedBox(height: AuraSpace.xxs),
          Text(caption,
              style: text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }
}

class _ExportButton extends StatelessWidget {
  const _ExportButton({required this.records, required this.connection});

  final List<ApiRequestRecord> records;
  final DashboardConnectionStatus connection;

  Future<void> _export(BuildContext context) async {
    try {
      final Directory directory = await LocalPaths.documents();
      final File file = File('${directory.path}/aura_hub_diagnostics.json');
      final Map<String, dynamic> payload = <String, dynamic>{
        'app': AppInfo.name,
        'version': AppInfo.version,
        'exportedAt': DateTime.now().toIso8601String(),
        'connection': <String, dynamic>{
          'label': connection.label,
          'lastSuccess': connection.lastSuccess?.toIso8601String(),
          'error': connection.error?.toString(),
        },
        'requests':
            records.map((ApiRequestRecord record) => record.toJson()).toList(),
      };
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(payload),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Diagnostics exported to ${file.path}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => _export(context),
      icon: const Icon(Icons.file_download_outlined, size: 16),
      label: const Text('Export JSON'),
    );
  }
}
