import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

/// Makes the source explicit: this Windows PC, sampled by the local API.
/// AURA device telemetry is a different source and is not claimed here.
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
      title: 'Windows host telemetry',
      message:
          'CPU, memory, disk, network and uptime are measured on this Windows '
          'PC by the local API at $apiUrl. Sampled '
          '${formatRelativeTime(generatedAt)}. This is not AURA device data.',
      icon: Icons.desktop_windows_outlined,
      tone: AuraBannerTone.info,
      trailing: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 900) return const SizedBox.shrink();
          return const StatusPill(
            label: 'HOST API',
            color: AuraColors.success,
            dense: true,
          );
        },
      ),
    );
  }
}
