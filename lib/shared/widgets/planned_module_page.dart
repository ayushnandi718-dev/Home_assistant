import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

/// Explains honestly why a module is unavailable and what must exist first.
class _ReadinessCard extends StatelessWidget {
  const _ReadinessCard();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.hardware_outlined, color: AuraColors.secondary),
              const SizedBox(width: AuraSpace.sm),
              Text('Availability', style: text.titleLarge),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'This module needs real AURA hardware and a secure backend. Until '
            'they are part of this build, no commands are sent to devices and '
            'no simulated results are shown.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          Wrap(
            spacing: AuraSpace.sm,
            runSpacing: AuraSpace.sm,
            children: const <Widget>[
              StatusPill(
                label: 'ESP32 HARDWARE',
                color: AuraColors.textSecondary,
                dense: true,
              ),
              StatusPill(
                label: 'FIRMWARE',
                color: AuraColors.textSecondary,
                dense: true,
              ),
              StatusPill(
                label: 'AUTHENTICATED BACKEND',
                color: AuraColors.textSecondary,
                dense: true,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PlannedCapability {
  const PlannedCapability({
    required this.title,
    required this.description,
    this.icon = Icons.check_circle_outline_rounded,
  });

  final String title;
  final String description;
  final IconData icon;
}

/// Honest placeholder used by modules that are designed but not implemented.
class PlannedModulePage extends StatelessWidget {
  const PlannedModulePage({
    super.key,
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.phase,
    required this.icon,
    required this.capabilities,
    this.accent = AuraColors.primary,
    this.noteTitle,
    this.noteBody,
  });

  final String eyebrow;
  final String title;
  final String description;
  final String phase;
  final IconData icon;
  final Color accent;
  final List<PlannedCapability> capabilities;
  final String? noteTitle;
  final String? noteBody;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

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
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final Widget header = PageHeader(
                    eyebrow: eyebrow,
                    title: title,
                    description: description,
                    icon: icon,
                    accent: accent,
                  );
                  final Widget badge = StatusPill(
                    label: '$phase  /  PLANNED',
                    color: AuraColors.warning,
                    icon: Icons.schedule_rounded,
                  );
                  if (constraints.maxWidth < 900) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        header,
                        const SizedBox(height: AuraSpace.md),
                        badge,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(child: header),
                      const SizedBox(width: AuraSpace.md),
                      badge,
                    ],
                  );
                },
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'Foundation build',
                message:
                    'This module is intentionally not implemented yet. No commands are sent to hardware and no backend calls are made from this screen.',
                icon: Icons.construction_rounded,
                tone: AuraBannerTone.warning,
              ),
              if (noteTitle != null && noteBody != null) ...<Widget>[
                const SizedBox(height: AuraSpace.md),
                InfoBanner(
                  title: noteTitle!,
                  message: noteBody!,
                  icon: Icons.lock_outline_rounded,
                  tone: AuraBannerTone.privacy,
                ),
              ],
              const SizedBox(height: AuraSpace.md),
              const _ReadinessCard(),
              const SizedBox(height: AuraSpace.lg),
              Text('Planned capabilities', style: text.titleLarge),
              const SizedBox(height: AuraSpace.md),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final int columns = constraints.maxWidth >= 980
                      ? 3
                      : constraints.maxWidth >= 620
                          ? 2
                          : 1;
                  return GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: AuraSpace.md,
                      mainAxisSpacing: AuraSpace.md,
                      mainAxisExtent: 142,
                    ),
                    itemCount: capabilities.length,
                    itemBuilder: (BuildContext context, int index) {
                      final PlannedCapability item = capabilities[index];
                      return SurfaceCard(
                        padding: const EdgeInsets.all(AuraSpace.md),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Icon(item.icon, size: 18, color: accent),
                                const Spacer(),
                                StatusPill(
                                  label: 'PLANNED',
                                  color: AuraColors.textSecondary,
                                  dense: true,
                                ),
                              ],
                            ),
                            const SizedBox(height: AuraSpace.sm),
                            Text(
                              item.title,
                              style: text.titleSmall,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: AuraSpace.xxs),
                            Expanded(
                              child: Text(
                                item.description,
                                style: text.bodySmall,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
