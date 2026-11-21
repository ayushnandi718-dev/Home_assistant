import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Real diagnostic events only. Windows host activity is never relabelled as
/// device activity on mobile Home.
class MobileRecentActivityCard extends ConsumerWidget {
  const MobileRecentActivityCard({super.key, this.limit = 4});

  final int limit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<DiagnosticEvent> events = ref.watch(diagnosticEventsProvider);
    final TextTheme text = Theme.of(context).textTheme;
    // Only real device-facing events belong here. Host telemetry and local API
    // diagnostics stay in Diagnostics, where they are explained in full.
    final List<DiagnosticEvent> recent = events
        .where(
          (DiagnosticEvent event) =>
              event.category == DiagnosticCategory.deviceDiscovery ||
              event.category == DiagnosticCategory.devicePairing ||
              event.category == DiagnosticCategory.deviceConnection,
        )
        .take(limit)
        .toList();

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassContainer(
                width: 38,
                height: 38,
                padding: EdgeInsets.zero,
                radius: 11,
                blur: 0,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.primary.withValues(alpha: 0.28),
                child: const Icon(Icons.history_rounded,
                    size: 19, color: AuraColors.primary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: Text('Recent activity', style: text.titleLarge)),
              TextButton(
                onPressed: () => context.go(AppRoutes.diagnostics),
                child: const Text('View all'),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          if (recent.isEmpty)
            _EmptyActivity(text: text)
          else
            Column(
              children: <Widget>[
                for (int index = 0; index < recent.length; index++) ...<Widget>[
                  if (index > 0) const SizedBox(height: AuraSpace.sm),
                  _ActivityRow(event: recent[index], text: text),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _EmptyActivity extends StatelessWidget {
  const _EmptyActivity({required this.text});

  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(Icons.inbox_outlined, size: 22, color: AuraColors.textSecondary),
        const SizedBox(width: AuraSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('No recent activity', style: text.titleSmall),
              const SizedBox(height: AuraSpace.xxs),
              Text(
                'Real device connection and pairing events will appear here. '
                'Wallpaper, sync and firmware history need ESP32 support.',
                style: text.bodySmall?.copyWith(
                  color: AuraColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.event, required this.text});

  final DiagnosticEvent event;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final Color color =
        event.succeeded ? AuraColors.success : AuraColors.warning;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Icon(
          event.succeeded ? Icons.check_circle_outline : Icons.error_outline,
          size: 20,
          color: color,
        ),
        const SizedBox(width: AuraSpace.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                event.category.label,
                style: text.labelMedium?.copyWith(color: color),
              ),
              const SizedBox(height: 2),
              Text(
                event.message,
                style: text.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                formatRelativeTime(event.timestamp),
                style: text.bodySmall?.copyWith(
                  color: AuraColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
