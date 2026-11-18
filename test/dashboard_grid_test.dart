import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_grid.dart';
import 'package:flutter_test/flutter_test.dart';

DashboardWidgetConfig _config(
  DashboardWidgetId id,
  DashboardWidgetSize size,
) =>
    DashboardWidgetConfig(id: id, visible: true, size: size);

double _rowWidth(
  List<DashboardWidgetConfig> row,
  double availableWidth,
  int columns,
) {
  double width = 0;
  for (final DashboardWidgetConfig config in row) {
    width += DashboardGrid.spanWidth(
      DashboardGrid.spanFor(config, columns),
      availableWidth,
      columns,
    );
  }
  return width + DashboardGrid.gap * (row.length - 1);
}

void main() {
  group('DashboardGrid', () {
    test('collapses from three columns to two and one', () {
      expect(DashboardGrid.columnsFor(1200), 3);
      expect(DashboardGrid.columnsFor(900), 2);
      expect(DashboardGrid.columnsFor(460), 1);
    });

    test('one compact widget keeps a single-column width', () {
      final List<DashboardWidgetConfig> configs = <DashboardWidgetConfig>[
        _config(DashboardWidgetId.spotlight, DashboardWidgetSize.compact),
      ];
      final List<List<DashboardWidgetConfig>> rows =
          DashboardGrid.groupIntoRows(configs, 3);

      expect(rows, hasLength(1));
      expect(rows.single, hasLength(1));
      expect(DashboardGrid.spanFor(rows.single.single, 3), 1);
      expect(DashboardGrid.spanWidth(1, 1200, 3), 384);
      expect(_rowWidth(rows.single, 1200, 3), lessThan(1200));
    });

    test('multiple compact widgets pack three per row', () {
      final List<DashboardWidgetConfig> configs =
          List<DashboardWidgetConfig>.generate(
        4,
        (int index) => _config(
            DashboardWidgetId.values[index], DashboardWidgetSize.compact),
      );
      final List<List<DashboardWidgetConfig>> rows =
          DashboardGrid.groupIntoRows(configs, 3);

      expect(rows.map((List<DashboardWidgetConfig> row) => row.length),
          <int>[3, 1]);
      expect(_rowWidth(rows.first, 1200, 3), closeTo(1200, 0.001));
      expect(_rowWidth(rows.last, 1200, 3), 384);
    });

    test('medium widgets span two columns and pair with compact', () {
      final List<DashboardWidgetConfig> configs = <DashboardWidgetConfig>[
        _config(DashboardWidgetId.spotlight, DashboardWidgetSize.compact),
        _config(DashboardWidgetId.history, DashboardWidgetSize.medium),
      ];
      final List<List<DashboardWidgetConfig>> rows =
          DashboardGrid.groupIntoRows(configs, 3);

      expect(rows, hasLength(1));
      expect(rows.single, hasLength(2));
      expect(DashboardGrid.spanWidth(2, 1200, 3), closeTo(792, 0.001));
      expect(_rowWidth(rows.single, 1200, 3), closeTo(1200, 0.001));
    });

    test('a full-width widget owns its row without dragging neighbours', () {
      final List<DashboardWidgetConfig> configs = <DashboardWidgetConfig>[
        _config(DashboardWidgetId.spotlight, DashboardWidgetSize.compact),
        _config(DashboardWidgetId.overview, DashboardWidgetSize.full),
        _config(DashboardWidgetId.activity, DashboardWidgetSize.compact),
      ];
      final List<List<DashboardWidgetConfig>> rows =
          DashboardGrid.groupIntoRows(configs, 3);

      expect(
        rows.map((List<DashboardWidgetConfig> row) => row.single.id),
        <DashboardWidgetId>[
          DashboardWidgetId.spotlight,
          DashboardWidgetId.overview,
          DashboardWidgetId.activity,
        ],
      );
      expect(_rowWidth(rows[1], 1200, 3), closeTo(1200, 0.001));
    });

    test('incomplete rows preserve their intended spans', () {
      final List<DashboardWidgetConfig> configs = <DashboardWidgetConfig>[
        _config(DashboardWidgetId.history, DashboardWidgetSize.medium),
      ];
      final List<List<DashboardWidgetConfig>> rows =
          DashboardGrid.groupIntoRows(configs, 3);

      expect(DashboardGrid.spanWidth(2, 1200, 3), closeTo(792, 0.001));
      expect(_rowWidth(rows.single, 1200, 3), closeTo(792, 0.001));
    });

    test('narrow layouts clamp every saved span to one column', () {
      for (final DashboardWidgetSize size in DashboardWidgetSize.values) {
        final DashboardWidgetConfig config =
            _config(DashboardWidgetId.overview, size);
        expect(DashboardGrid.spanFor(config, 1), 1);
        expect(DashboardGrid.spanWidth(config.size.span, 428, 1), 428);
      }
    });

    test('no row exceeds the available width at supported breakpoints', () {
      for (final double width in <double>[
        1440,
        1280,
        1100,
        900,
        860,
        560,
        460,
        320
      ]) {
        final int columns = DashboardGrid.columnsFor(width);
        for (final DashboardWidgetSize size in DashboardWidgetSize.values) {
          final List<List<DashboardWidgetConfig>> rows =
              DashboardGrid.groupIntoRows(
            <DashboardWidgetConfig>[_config(DashboardWidgetId.overview, size)],
            columns,
          );
          expect(
            _rowWidth(rows.single, width, columns),
            lessThanOrEqualTo(width + 0.001),
            reason: '${size.name} at $width',
          );
        }
      }
    });

    test('uses the shared spacing token', () {
      expect(DashboardGrid.gap, AuraSpace.lg);
    });
  });
}
