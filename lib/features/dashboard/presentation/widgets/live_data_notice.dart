import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

/// Makes the source of every dashboard value explicit: this Windows host,
/// sampled by the local AURA telemetry API.
class LiveDataNotice extends StatelessWidget {
  const LiveDataNotice({
    super.key,
    required this.apiUrl,
    required this.generatedAt,
  });

  final String apiUrl;
  final DateTime generatedAt;

  @override
  Widget build(BuildContext context) {
    return InfoBanner(
      title: 'Live local telemetry',
      message:
          'CPU, memory, disk, network, uptime and battery are measured on this '
          'Windows host by the AURA API at $apiUrl. Sampled '
          '${formatRelativeTime(generatedAt)}.',
      icon: Icons.cloud_done_outlined,
      tone: AuraBannerTone.info,
      trailing: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 900) return const SizedBox.shrink();
          return const StatusPill(
            label: 'LIVE API',
            color: AuraColors.success,
            dense: true,
          );
        },
      ),
    );
  }
}
