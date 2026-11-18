import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';

/// Pure layout maths for the dashboard's responsive bento grid.
///
/// Keeping this independent of widgets makes the sizing rules easy to test and
/// avoids recomputing them more than once per layout pass.
abstract final class DashboardGrid {
  static const int maxColumns = 3;
  static const double gap = AuraSpace.lg;

  static int columnsFor(double width) {
    if (width >= 1100) return 3;
    if (width >= 560) return 2;
    return 1;
  }

  /// Clamps a saved size to the columns actually available at this width.
  static int spanFor(DashboardWidgetConfig config, int columns) {
    if (columns <= 1) return 1;
    final int span = config.size.span;
    return span > columns ? columns : span;
  }

  /// Greedily packs visible widgets into rows without exceeding [columns].
  /// Hidden widgets are already removed by the caller; order is preserved.
  static List<List<DashboardWidgetConfig>> groupIntoRows(
    List<DashboardWidgetConfig> configs,
    int columns,
  ) {
    final List<List<DashboardWidgetConfig>> rows =
        <List<DashboardWidgetConfig>>[];
    List<DashboardWidgetConfig> row = <DashboardWidgetConfig>[];
    int used = 0;

    for (final DashboardWidgetConfig config in configs) {
      final int span = spanFor(config, columns);
      if (row.isNotEmpty && used + span > columns) {
        rows.add(row);
        row = <DashboardWidgetConfig>[];
        used = 0;
      }
      row.add(config);
      used += span;
      if (used == columns) {
        rows.add(row);
        row = <DashboardWidgetConfig>[];
        used = 0;
      }
    }
    if (row.isNotEmpty) rows.add(row);
    return rows;
  }

  static double columnWidth(double availableWidth, int columns) {
    if (columns <= 1) return availableWidth;
    final double usable = availableWidth - gap * (columns - 1);
    return usable <= 0 ? 0 : usable / columns;
  }

  /// Width of one card spanning [span] columns, including its internal gaps.
  ///
  /// A compact card therefore stays one column wide even when it is the only
  /// child in an incomplete row.
  static double spanWidth(
    int span,
    double availableWidth,
    int columns,
  ) {
    final int clamped = span < 1 ? 1 : (span > columns ? columns : span);
    return columnWidth(availableWidth, columns) * clamped + gap * (clamped - 1);
  }
}
