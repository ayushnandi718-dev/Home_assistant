import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/dashboard/data/dashboard_layout_store.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardLayout', () {
    test('defaults include every widget and all are visible', () {
      final DashboardLayout layout = DashboardLayout.defaults;
      expect(layout.widgets.length, DashboardWidgetId.values.length);
      for (final DashboardWidgetId id in DashboardWidgetId.values) {
        expect(layout.isVisible(id), isTrue, reason: id.name);
      }
    });

    test('toggle flips only the requested widget', () {
      final DashboardLayout next =
          DashboardLayout.defaults.toggle(DashboardWidgetId.history);
      expect(next.isVisible(DashboardWidgetId.history), isFalse);
      expect(next.isVisible(DashboardWidgetId.overview), isTrue);
      expect(
        next.toggle(DashboardWidgetId.history),
        DashboardLayout.defaults,
      );
    });

    test('reorder moves an item and clamps an oversized target', () {
      final DashboardLayout original = DashboardLayout.defaults;
      final DashboardLayout moved = original.reorder(0, 2);
      expect(moved.widgets[0].id, DashboardWidgetId.history);
      expect(moved.widgets[1].id, DashboardWidgetId.overview);

      final DashboardLayout clamped = original.reorder(0, 999);
      expect(clamped.widgets.last.id, DashboardWidgetId.overview);

      expect(original.reorder(-1, 1), same(original));
    });

    test('equality depends on order and visibility', () {
      final DashboardLayout reordered = DashboardLayout.defaults.reorder(0, 2);
      expect(reordered, isNot(DashboardLayout.defaults));
      expect(reordered.hashCode, isNot(DashboardLayout.defaults.hashCode));
    });

    test('fromJson drops unknown and duplicate ids and appends missing ones',
        () {
      final DashboardLayout restored = DashboardLayout.fromJson(
        <String, dynamic>{
          'version': 1,
          'widgets': <dynamic>[
            <String, dynamic>{'id': 'bogus', 'visible': true},
            <String, dynamic>{'id': 'activity', 'visible': false},
            <String, dynamic>{'id': 'activity', 'visible': true},
          ],
        },
      );

      expect(restored.widgets.length, DashboardWidgetId.values.length);
      expect(restored.widgets.first.id, DashboardWidgetId.activity);
      expect(restored.isVisible(DashboardWidgetId.activity), isFalse);
      expect(restored.isVisible(DashboardWidgetId.overview), isTrue);
    });

    test('fromJson falls back to defaults for malformed input', () {
      expect(DashboardLayout.fromJson(null), DashboardLayout.defaults);
      expect(DashboardLayout.fromJson(<String, dynamic>{}),
          DashboardLayout.defaults);
      expect(DashboardLayout.fromJson(<String, dynamic>{'widgets': 'oops'}),
          DashboardLayout.defaults);
    });

    test('toJson round trips a customised layout', () {
      final DashboardLayout custom = DashboardLayout.defaults
          .toggle(DashboardWidgetId.activity)
          .reorder(5, 1);
      final Object? decoded = jsonDecode(jsonEncode(custom.toJson()));
      expect(DashboardLayout.fromJson(decoded), custom);
    });
  });

  group('DashboardLayoutStore', () {
    late Directory directory;

    setUp(() {
      directory = Directory.systemTemp.createTempSync('aura_layout_test_');
    });

    tearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });

    test('persists a customised layout across reload', () async {
      final DashboardLayoutStore store =
          DashboardLayoutStore(directory: directory);
      final DashboardLayout custom = DashboardLayout.defaults
          .toggle(DashboardWidgetId.notifications)
          .reorder(1, 4);

      await store.save(custom);
      final DashboardLayout reloaded = await DashboardLayoutStore(
        directory: directory,
      ).load();

      expect(reloaded, custom);
    });

    test('falls back to defaults for a corrupt file', () async {
      final DashboardLayoutStore store =
          DashboardLayoutStore(directory: directory);
      await store.save(DashboardLayout.defaults);
      final File file = File(
        '${directory.path}${Platform.pathSeparator}dashboard_layout.json',
      );
      await file.writeAsString('{not json');

      expect(await store.load(), DashboardLayout.defaults);
    });
  });
}
