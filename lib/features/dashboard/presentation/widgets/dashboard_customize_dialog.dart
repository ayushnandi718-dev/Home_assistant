import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lets the user reorder dashboard widgets by dragging and hide/show them.
/// Preferences are persisted immediately by [DashboardLayoutController].
class DashboardCustomizeDialog extends ConsumerWidget {
  const DashboardCustomizeDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DashboardLayout layout = ref.watch(dashboardLayoutProvider);
    final DashboardLayoutController controller =
        ref.read(dashboardLayoutProvider.notifier);
    final TextTheme text = Theme.of(context).textTheme;

    return GlassDialog(
      width: 520,
      padding: const EdgeInsets.all(AuraSpace.lg),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 640),
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
                      Text('CUSTOMIZE DASHBOARD', style: text.labelMedium),
                      const SizedBox(height: AuraSpace.xxs),
                      Text('Widgets', style: text.headlineSmall),
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
            Text(
              'Drag a widget to change its order. Use the eye icon to hide '
              'or show it. Source and health banners always stay visible.',
              style: text.bodyMedium,
            ),
            const SizedBox(height: AuraSpace.md),
            Flexible(
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: layout.widgets.length,
                onReorder: controller.reorder,
                itemBuilder: (BuildContext context, int index) {
                  final DashboardWidgetConfig item = layout.widgets[index];
                  return GlassContainer(
                    key: ValueKey<String>(item.id.name),
                    surface: AuraGlassSurface.panel,
                    radius: AuraRadius.control,
                    blur: 8,
                    fill: 0.5,
                    padding: EdgeInsets.zero,
                    margin: const EdgeInsets.only(bottom: AuraSpace.xs),
                    child: ListTile(
                      leading: Icon(
                        _iconFor(item.id),
                        size: 20,
                        color: item.visible
                            ? AuraColors.primary
                            : AuraColors.textSecondary,
                      ),
                      title: Text(item.id.label, style: text.titleSmall),
                      subtitle: Text(
                        item.id.description,
                        style: text.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        tooltip: item.visible ? 'Hide widget' : 'Show widget',
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
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: AuraSpace.md),
            Row(
              children: <Widget>[
                TextButton.icon(
                  onPressed: controller.reset,
                  icon: const Icon(Icons.restore_rounded, size: 16),
                  label: const Text('Restore defaults'),
                ),
                const Spacer(),
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
