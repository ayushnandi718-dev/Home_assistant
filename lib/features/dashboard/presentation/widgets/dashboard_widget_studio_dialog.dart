import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Desktop editor for the active workspace's dashboard.
///
/// Drag rows to arrange widgets, choose a column span, and hide anything that
/// is not needed. Every change is persisted by [DashboardLayoutController] to
/// the active profile's own file.
class DashboardWidgetStudioDialog extends ConsumerWidget {
  const DashboardWidgetStudioDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DashboardLayout layout = ref.watch(dashboardLayoutProvider);
    final DashboardLayoutController controller =
        ref.read(activeDashboardLayoutControllerProvider);
    final AuraProfile profile = ref.watch(activeProfileProvider);
    final TextTheme text = Theme.of(context).textTheme;
    final Color accent = profile == AuraProfile.ayush
        ? AuraColors.secondary
        : AuraColors.primary;

    return GlassDialog(
      width: 720,
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text('WIDGET STUDIO', style: text.labelMedium),
                      const SizedBox(height: AuraSpace.xxs),
                      Text('Dashboard layout', style: text.headlineSmall),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ],
            ),
            const SizedBox(height: AuraSpace.sm),
            _ProfileBanner(profile: profile, accent: accent),
            const SizedBox(height: AuraSpace.md),
            Text(
              'Drag to arrange. Choose a size to give a widget more or less '
              'room. Use the eye icon to hide it. Source and health banners '
              'always stay visible.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: AuraSpace.md),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                buildDefaultDragHandles: false,
                itemCount: layout.widgets.length,
                onReorder: controller.reorder,
                proxyDecorator:
                    (Widget child, int index, Animation<double> animation) =>
                        Material(
                  color: Colors.transparent,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(AuraRadius.control),
                  child: child,
                ),
                itemBuilder: (BuildContext context, int index) {
                  final DashboardWidgetConfig item = layout.widgets[index];
                  return GlassContainer(
                    key: ValueKey<String>(item.id.name),
                    surface: AuraGlassSurface.panel,
                    radius: AuraRadius.control,
                    blur: 0,
                    fill: 0.62,
                    padding: EdgeInsets.zero,
                    margin: const EdgeInsets.only(bottom: AuraSpace.xs),
                    child: ListTile(
                      leading: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            _iconFor(item.id),
                            size: 20,
                            color: item.visible
                                ? accent
                                : AuraColors.textSecondary,
                          ),
                          const SizedBox(width: AuraSpace.xxs),
                          Tooltip(
                            message: 'Drag to reorder',
                            child: ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(AuraSpace.xxs),
                                child: Icon(
                                  Icons.drag_indicator_rounded,
                                  size: 16,
                                  color: AuraColors.textSecondary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      title: Text(item.id.label, style: text.titleSmall),
                      subtitle: Text(
                        '${item.id.description}  ·  ${item.size.label} '
                        '(${item.size.span} col${item.size.span == 1 ? '' : 's'})',
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          PopupMenuButton<DashboardWidgetSize>(
                            tooltip: 'Widget size',
                            initialValue: item.size,
                            onSelected: (DashboardWidgetSize size) =>
                                controller.setSize(item.id, size),
                            icon: const Icon(Icons.view_module_outlined,
                                size: 18),
                            itemBuilder: (BuildContext context) =>
                                <PopupMenuEntry<DashboardWidgetSize>>[
                              for (final DashboardWidgetSize size
                                  in DashboardWidgetSize.values)
                                PopupMenuItem<DashboardWidgetSize>(
                                  value: size,
                                  child: Row(
                                    children: <Widget>[
                                      Icon(
                                        size == item.size
                                            ? Icons.check_rounded
                                            : Icons.circle_outlined,
                                        size: 15,
                                        color: size == item.size
                                            ? accent
                                            : AuraColors.textSecondary,
                                      ),
                                      const SizedBox(width: AuraSpace.xs),
                                      Text(size.label),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                          IconButton(
                            tooltip:
                                item.visible ? 'Hide widget' : 'Show widget',
                            onPressed: () => controller.toggle(item.id),
                            icon: Icon(
                              item.visible
                                  ? Icons.visibility_rounded
                                  : Icons.visibility_off_rounded,
                              size: 20,
                              color: item.visible
                                  ? AuraColors.success
                                  : AuraColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AuraSpace.md),
            Wrap(
              spacing: AuraSpace.sm,
              runSpacing: AuraSpace.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: <Widget>[
                TextButton.icon(
                  onPressed: () => _confirmReset(context, ref, profile),
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: Text('Reset ${profile.label} layout'),
                ),
                ValueListenableBuilder<DashboardLayoutSaveState>(
                  valueListenable: controller.saveState,
                  builder: (
                    BuildContext context,
                    DashboardLayoutSaveState state,
                    Widget? child,
                  ) {
                    return Text(
                      state.label,
                      style: text.bodySmall?.copyWith(
                        color: state == DashboardLayoutSaveState.failed
                            ? AuraColors.danger
                            : AuraColors.textSecondary,
                      ),
                    );
                  },
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Done'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(
    BuildContext context,
    WidgetRef ref,
    AuraProfile profile,
  ) async {
    final bool? confirmed = await showGlassDialog<bool>(
      context: context,
      width: 440,
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: _ResetConfirmationDialog(profile: profile),
    );
    if (confirmed != true || !context.mounted) return;
    await ref.read(activeDashboardLayoutControllerProvider).reset();
  }

  IconData _iconFor(DashboardWidgetId id) {
    switch (id) {
      case DashboardWidgetId.overview:
        return Icons.space_dashboard_outlined;
      case DashboardWidgetId.history:
        return Icons.show_chart_rounded;
      case DashboardWidgetId.spotlight:
        return Icons.devices_other_outlined;
      case DashboardWidgetId.quickActions:
        return Icons.bolt_outlined;
      case DashboardWidgetId.activity:
        return Icons.history_rounded;
      case DashboardWidgetId.notifications:
        return Icons.notifications_none_rounded;
    }
  }
}

class _ResetConfirmationDialog extends StatelessWidget {
  const _ResetConfirmationDialog({required this.profile});

  final AuraProfile profile;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Reset layout?', style: text.titleLarge),
        const SizedBox(height: AuraSpace.sm),
        Text(
          'This restores the default widgets, sizes and order for the '
          '${profile.label} workspace only. The other workspace keeps its '
          'saved layout.',
          style: text.bodyMedium,
        ),
        const SizedBox(height: AuraSpace.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AuraSpace.sm),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Reset layout'),
            ),
          ],
        ),
      ],
    );
  }
}

class _ProfileBanner extends StatelessWidget {
  const _ProfileBanner({required this.profile, required this.accent});

  final AuraProfile profile;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return GlassContainer(
      surface: AuraGlassSurface.panel,
      radius: AuraRadius.control,
      blur: 0,
      fill: 0.62,
      padding: const EdgeInsets.symmetric(
        horizontal: AuraSpace.md,
        vertical: AuraSpace.sm,
      ),
      child: Row(
        children: <Widget>[
          Icon(
            profile == AuraProfile.ayush
                ? Icons.lock_outline_rounded
                : Icons.family_restroom_outlined,
            size: 18,
            color: accent,
          ),
          const SizedBox(width: AuraSpace.sm),
          Expanded(
            child: Text(
              'Editing the ${profile.label} workspace layout. '
              'Other workspaces keep their own saved layout.',
              style: text.bodySmall,
            ),
          ),
          const SizedBox(width: AuraSpace.sm),
          StatusPill(
            label: profile.label,
            color: accent,
            showDot: false,
            dense: true,
          ),
        ],
      ),
    );
  }
}
