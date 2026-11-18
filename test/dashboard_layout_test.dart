import 'dart:convert';
import 'dart:io';

import 'package:aura_hub/features/dashboard/data/dashboard_layout_store.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DashboardLayout', () {
    test('defaults include every widget with a balanced bento size', () {
      final DashboardLayout layout = DashboardLayout.defaults;
      expect(layout.widgets.length, DashboardWidgetId.values.length);
      for (final DashboardWidgetId id in DashboardWidgetId.values) {
        expect(layout.isVisible(id), isTrue, reason: id.name);
      }
      expect(
          layout.sizeOf(DashboardWidgetId.overview), DashboardWidgetSize.full);
      expect(
          layout.sizeOf(DashboardWidgetId.history), DashboardWidgetSize.medium);
      expect(layout.sizeOf(DashboardWidgetId.spotlight),
          DashboardWidgetSize.compact);
      expect(layout.sizeOf(DashboardWidgetId.quickActions),
          DashboardWidgetSize.compact);
      expect(layout.sizeOf(DashboardWidgetId.activity),
          DashboardWidgetSize.medium);
      expect(layout.sizeOf(DashboardWidgetId.notifications),
          DashboardWidgetSize.full);
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

    test('setSize changes only the requested widget', () {
      final DashboardLayout resized = DashboardLayout.defaults.setSize(
        DashboardWidgetId.history,
        DashboardWidgetSize.full,
      );
      expect(
        resized.sizeOf(DashboardWidgetId.history),
        DashboardWidgetSize.full,
      );
      expect(
        resized.sizeOf(DashboardWidgetId.overview),
        DashboardWidgetSize.full,
      );
      expect(resized.isVisible(DashboardWidgetId.history), isTrue);
      expect(resized, isNot(DashboardLayout.defaults));
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

    test('equality depends on order, visibility and size', () {
      final DashboardLayout reordered = DashboardLayout.defaults.reorder(0, 2);
      expect(reordered, isNot(DashboardLayout.defaults));
      expect(reordered.hashCode, isNot(DashboardLayout.defaults.hashCode));

      final DashboardLayout resized = DashboardLayout.defaults.setSize(
        DashboardWidgetId.activity,
        DashboardWidgetSize.compact,
      );
      expect(resized, isNot(DashboardLayout.defaults));
      expect(resized.hashCode, isNot(DashboardLayout.defaults.hashCode));
    });

    test('fromJson drops unknown and duplicate ids and appends missing ones',
        () {
      final DashboardLayout restored = DashboardLayout.fromJson(
        <String, dynamic>{
          'version': 2,
          'widgets': <dynamic>[
            <String, dynamic>{'id': 'bogus', 'visible': true},
            <String, dynamic>{
              'id': 'activity',
              'visible': false,
              'size': 'compact',
            },
            <String, dynamic>{'id': 'activity', 'visible': true},
          ],
        },
      );

      expect(restored.widgets.length, DashboardWidgetId.values.length);
      expect(restored.widgets.first.id, DashboardWidgetId.activity);
      expect(restored.isVisible(DashboardWidgetId.activity), isFalse);
      expect(
        restored.sizeOf(DashboardWidgetId.activity),
        DashboardWidgetSize.compact,
      );
      expect(restored.isVisible(DashboardWidgetId.overview), isTrue);
    });

    test('fromJson gives version 1 entries their default sizes', () {
      final DashboardLayout restored = DashboardLayout.fromJson(
        <String, dynamic>{
          'version': 1,
          'widgets': <dynamic>[
            <String, dynamic>{'id': 'activity', 'visible': true},
          ],
        },
      );

      expect(
        restored.sizeOf(DashboardWidgetId.activity),
        DashboardWidgetSize.medium,
      );
    });

    test('fromJson replaces an invalid size with the default', () {
      final DashboardLayout restored = DashboardLayout.fromJson(
        <String, dynamic>{
          'version': 2,
          'widgets': <dynamic>[
            <String, dynamic>{
              'id': 'overview',
              'visible': true,
              'size': 'enormous',
            },
          ],
        },
      );

      expect(
        restored.sizeOf(DashboardWidgetId.overview),
        DashboardWidgetSize.full,
      );
    });

    test('fromJson falls back to defaults for malformed input', () {
      expect(DashboardLayout.fromJson(null), DashboardLayout.defaults);
      expect(DashboardLayout.fromJson(<String, dynamic>{}),
          DashboardLayout.defaults);
      expect(DashboardLayout.fromJson(<String, dynamic>{'widgets': 'oops'}),
          DashboardLayout.defaults);
    });

    test('toJson round trips a customised v2 layout', () {
      final DashboardLayout custom = DashboardLayout.defaults
          .toggle(DashboardWidgetId.activity)
          .setSize(DashboardWidgetId.history, DashboardWidgetSize.full)
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
      final DashboardLayoutStore store = DashboardLayoutStore(
          directory: directory, profile: AuraProfile.family);
      final DashboardLayout custom = DashboardLayout.defaults
          .toggle(DashboardWidgetId.notifications)
          .setSize(DashboardWidgetId.history, DashboardWidgetSize.compact)
          .reorder(1, 4);

      await store.save(custom);
      final DashboardLayout reloaded = await DashboardLayoutStore(
        directory: directory,
        profile: AuraProfile.family,
      ).load();

      expect(reloaded, custom);
    });

    test('AYUSH and FAMILY layouts are stored independently', () async {
      final DashboardLayoutStore family = DashboardLayoutStore(
          directory: directory, profile: AuraProfile.family);
      final DashboardLayoutStore ayush = DashboardLayoutStore(
          directory: directory, profile: AuraProfile.ayush);
      final DashboardLayout familyLayout =
          DashboardLayout.defaults.toggle(DashboardWidgetId.activity);
      final DashboardLayout ayushLayout = DashboardLayout.defaults
          .toggle(DashboardWidgetId.history)
          .setSize(DashboardWidgetId.overview, DashboardWidgetSize.medium);

      await family.save(familyLayout);
      await ayush.save(ayushLayout);

      expect(family.filePath, contains('dashboard_layout_family.json'));
      expect(ayush.filePath, contains('dashboard_layout_ayush.json'));
      expect(await family.load(), familyLayout);
      expect(await ayush.load(), ayushLayout);
      expect(await family.load(), isNot(ayushLayout));
    });

    test('migrates the legacy shared layout into each workspace', () async {
      final DashboardLayout legacyLayout = DashboardLayout.defaults
          .toggle(DashboardWidgetId.activity)
          .reorder(1, 3);
      await DashboardLayoutStore(directory: directory).save(legacyLayout);

      final DashboardLayout family = await DashboardLayoutStore(
        directory: directory,
        profile: AuraProfile.family,
      ).load();
      expect(family, legacyLayout);

      await DashboardLayoutStore(
        directory: directory,
        profile: AuraProfile.family,
      ).save(DashboardLayout.defaults);

      final DashboardLayout ayush = await DashboardLayoutStore(
        directory: directory,
        profile: AuraProfile.ayush,
      ).load();
      expect(ayush, legacyLayout);
    });

    test('falls back to defaults for a corrupt file', () async {
      final DashboardLayoutStore store = DashboardLayoutStore(
          directory: directory, profile: AuraProfile.family);
      await store.save(DashboardLayout.defaults);
      final File file = File(store.filePath);
      await file.writeAsString('{not json');

      expect(await store.load(), DashboardLayout.defaults);
    });
  });
}
