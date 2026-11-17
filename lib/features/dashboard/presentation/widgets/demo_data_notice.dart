import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

class DemoDataNotice extends StatelessWidget {
  const DemoDataNotice({super.key});

  @override
  Widget build(BuildContext context) {
    return InfoBanner(
      title: 'Demonstration data',
      message:
          'Device records, activity and statuses below come from a local mock repository. AURA Core is not connected and no hardware telemetry is live.',
      icon: Icons.science_outlined,
      tone: AuraBannerTone.warning,
      trailing: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          if (constraints.maxWidth < 900) return const SizedBox.shrink();
          return const StatusPill(
            label: 'MOCK REPOSITORY',
            color: AuraColors.warning,
            dense: true,
          );
        },
      ),
    );
  }
}
