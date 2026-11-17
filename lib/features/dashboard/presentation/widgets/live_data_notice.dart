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
    this.stale = false,
  });

  final String apiUrl;
  final DateTime generatedAt;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final String when = formatRelativeTime(generatedAt);
    return InfoBanner(
      title: 'Windows host telemetry',
      message: stale
          ? 'Reconnecting to the local API at $apiUrl. Keeping the last '
              'successful sample from $when and retrying automatically. '
              'These are PC readings, not AURA device data.'
          : 'CPU, memory, disk, network and uptime are measured on this Windows '
              'PC by the local API at $apiUrl. Last synced $when. '
              'These are PC readings, not AURA device data.',
      icon: stale ? Icons.cloud_off_outlined : Icons.desktop_windows_outlined,
      tone: stale ? AuraBannerTone.warning : AuraBannerTone.info,
      trailing: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 900) return const SizedBox.shrink();
          return StatusPill(
            label: stale ? 'RECONNECTING' : 'HOST API',
            color: stale ? AuraColors.warning : AuraColors.success,
            dense: true,
          );
        },
      ),
    );
  }
}
