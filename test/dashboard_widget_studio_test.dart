import 'dart:io';

import 'package:aura_hub/features/dashboard/data/dashboard_layout_store.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/dashboard_widget_studio_dialog.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryLayoutStore extends DashboardLayoutStore {
  _MemoryLayoutStore(Directory directory, AuraProfile profile)
      : super(directory: directory, profile: profile);

  DashboardLayout _layout = DashboardLayout.defaults;
  int saveCount = 0;
  bool failSaves = false;

  @override
  Future<DashboardLayout> load() async => _layout;

  @override
  Future<bool> save(DashboardLayout layout) async {
    if (failSaves) return false;
    _layout = layout;
    saveCount++;
    return true;
  }
}

void main() {
  late Directory directory;
  late Map<AuraProfile, _MemoryLayoutStore> stores;
  late ProviderContainer container;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('aura_studio_test_');
    stores = <AuraProfile, _MemoryLayoutStore>{
      for (final AuraProfile profile in AuraProfile.values)
        profile: _MemoryLayoutStore(directory, profile),
    };
    container = ProviderContainer(
      overrides: <Override>[
        dashboardLayoutForProvider.overrideWith(
          (Ref ref, AuraProfile profile) => DashboardLayoutController(
            store: stores[profile]!,
          ),
        ),
      ],
    );
  });

  tearDown(() {
    container.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<void> pumpStudio(WidgetTester tester) async {
    // ReorderableListView.builder only builds the visible window; use a desktop
    // viewport so every row is laid out, matching the Windows target.
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: DashboardWidgetStudioDialog()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> confirmReset(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Reset layout'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the active workspace and a drag list',
      (WidgetTester tester) async {
    await pumpStudio(tester);

    expect(find.text('WIDGET STUDIO'), findsOneWidget);
    expect(
      find.textContaining('Editing the FAMILY workspace layout'),
      findsOneWidget,
    );
    expect(find.byType(ReorderableListView), findsOneWidget);
    expect(find.byType(ReorderableDragStartListener), findsNWidgets(6));
    for (final DashboardWidgetId id in DashboardWidgetId.values) {
      expect(find.text(id.label), findsOneWidget, reason: id.name);
      expect(find.textContaining(id.description), findsOneWidget);
    }
    for (final DashboardWidgetSize size in DashboardWidgetSize.values) {
      expect(find.textContaining(size.label), findsWidgets);
    }
  });

  testWidgets('size selection persists to the active layout',
      (WidgetTester tester) async {
    await pumpStudio(tester);

    await tester.tap(find.byTooltip('Widget size').at(1));
    await tester.pumpAndSettle();
    await tester.tap(
      find.widgetWithText(PopupMenuItem<DashboardWidgetSize>, 'Full width'),
    );
    await tester.pumpAndSettle();

    final DashboardLayout layout = container.read(dashboardLayoutProvider);
    expect(
      layout.sizeOf(DashboardWidgetId.history),
      DashboardWidgetSize.full,
    );
    expect(stores[AuraProfile.family]!.saveCount, 1);
    expect(find.text('Saved locally'), findsOneWidget);
  });

  testWidgets('visibility toggle hides only the chosen widget',
      (WidgetTester tester) async {
    await pumpStudio(tester);

    await tester.tap(find.byTooltip('Hide widget').first);
    await tester.pumpAndSettle();

    final DashboardLayout layout = container.read(dashboardLayoutProvider);
    expect(layout.isVisible(DashboardWidgetId.overview), isFalse);
    expect(layout.isVisible(DashboardWidgetId.history), isTrue);
    expect(stores[AuraProfile.family]!.saveCount, 1);
    expect(find.text('Saved locally'), findsOneWidget);
  });

  testWidgets('drag handles reorder the active layout',
      (WidgetTester tester) async {
    await pumpStudio(tester);

    await tester.drag(
      find.byType(ReorderableDragStartListener).first,
      const Offset(0, 160),
    );
    await tester.pumpAndSettle();

    final DashboardLayout layout = container.read(dashboardLayoutProvider);
    expect(
      layout.widgets.first.id,
      DashboardWidgetId.history,
      reason: 'dragging the first row below the second should swap them',
    );
    expect(stores[AuraProfile.family]!.saveCount, 1);
    expect(find.text('Saved locally'), findsOneWidget);
  });

  testWidgets('reports an unsuccessful save instead of claiming success',
      (WidgetTester tester) async {
    stores[AuraProfile.family]!.failSaves = true;
    await pumpStudio(tester);

    await tester.tap(find.byTooltip('Hide widget').first);
    await tester.pumpAndSettle();

    expect(find.text('Could not save locally'), findsOneWidget);
    expect(find.text('Saved locally'), findsNothing);
    expect(stores[AuraProfile.family]!.saveCount, 0);
  });

  testWidgets('reset asks for confirmation and can be cancelled',
      (WidgetTester tester) async {
    await pumpStudio(tester);

    await tester.tap(find.byTooltip('Hide widget').first);
    await tester.pumpAndSettle();
    expect(container.read(dashboardLayoutProvider),
        isNot(DashboardLayout.defaults));

    await tester.tap(find.widgetWithText(TextButton, 'Reset FAMILY layout'));
    await tester.pumpAndSettle();
    expect(find.text('Reset layout?'), findsOneWidget);
    expect(
      find.textContaining('for the FAMILY workspace only'),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(dashboardLayoutProvider),
        isNot(DashboardLayout.defaults));
    expect(
      container
          .read(dashboardLayoutProvider)
          .isVisible(DashboardWidgetId.overview),
      isFalse,
    );

    await tester.tap(find.widgetWithText(TextButton, 'Reset FAMILY layout'));
    await tester.pumpAndSettle();
    await confirmReset(tester);

    expect(container.read(dashboardLayoutProvider), DashboardLayout.defaults);
    expect(stores[AuraProfile.family]!._layout, DashboardLayout.defaults);
  });

  testWidgets(
      'switching workspace swaps layouts and resets only the active one',
      (WidgetTester tester) async {
    await pumpStudio(tester);

    // Hide overview in FAMILY.
    await tester.tap(find.byTooltip('Hide widget').first);
    await tester.pumpAndSettle();
    final int familySaves = stores[AuraProfile.family]!.saveCount;

    // Switch to the private workspace without using a PIN: the test only
    // exercises layout routing, not authentication.
    container.read(profileSessionProvider.notifier).state = ProfileSession(
      profile: AuraProfile.ayush,
      startedAt: DateTime.now(),
      authenticated: true,
    );
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Editing the AYUSH workspace layout'),
      findsOneWidget,
    );
    expect(
        find.widgetWithText(TextButton, 'Reset AYUSH layout'), findsOneWidget);
    expect(container.read(dashboardLayoutProvider), DashboardLayout.defaults);

    // Hide history in AYUSH; FAMILY must keep its own edit untouched.
    await tester.tap(find.byTooltip('Hide widget').at(1));
    await tester.pumpAndSettle();

    final DashboardLayout family = stores[AuraProfile.family]!._layout;
    final DashboardLayout ayush = stores[AuraProfile.ayush]!._layout;
    expect(family.isVisible(DashboardWidgetId.overview), isFalse);
    expect(family.isVisible(DashboardWidgetId.history), isTrue);
    expect(stores[AuraProfile.family]!.saveCount, familySaves);
    expect(ayush.isVisible(DashboardWidgetId.overview), isTrue);
    expect(ayush.isVisible(DashboardWidgetId.history), isFalse);
    expect(stores[AuraProfile.ayush]!.saveCount, 1);

    // Resetting AYUSH must not restore FAMILY's hidden overview.
    await tester.tap(find.widgetWithText(TextButton, 'Reset AYUSH layout'));
    await tester.pumpAndSettle();
    await confirmReset(tester);

    expect(container.read(dashboardLayoutProvider), DashboardLayout.defaults);
    expect(stores[AuraProfile.family]!._layout, family);
    expect(stores[AuraProfile.ayush]!._layout, DashboardLayout.defaults);
  });
}
