import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/shared/widgets/glass/glass_badge.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/shared/widgets/glass/glass_section_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Glass design tokens', () {
    test('data cards are opaque and skip backdrop blur', () {
      expect(AuraGlass.specCard.fill, greaterThan(AuraGlass.specChrome.fill));
      expect(AuraGlass.specCard.blur, 0);
      expect(AuraGlass.specStrong.blur, 0);
      expect(AuraGlass.specPanel.blur, 0);
      expect(AuraGlass.specChrome.blur, greaterThan(0));
      expect(AuraGlass.specFloating.blur,
          greaterThanOrEqualTo(AuraGlass.specChrome.blur));
    });

    test('every surface has a visible fill and border', () {
      for (final AuraGlassSurface surface in AuraGlassSurface.values) {
        final AuraGlassSpec spec = AuraGlass.spec(surface);
        expect(spec.fill, greaterThan(0));
        expect(spec.fill, lessThanOrEqualTo(1));
        expect(spec.borderAlpha, greaterThan(0));
        expect(spec.shadows, isNotEmpty);
      }
    });
  });

  group('GlassContainer', () {
    testWidgets('renders its child and handles taps',
        (WidgetTester tester) async {
      int taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GlassContainer(
            onTap: () => taps++,
            child: const Text('glass content'),
          ),
        ),
      ));

      expect(find.text('glass content'), findsOneWidget);
      await tester.tap(find.text('glass content'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('renders without a backdrop filter when blur is disabled',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GlassContainer(
            surface: AuraGlassSurface.panel,
            child: Text('no blur'),
          ),
        ),
      ));

      expect(find.text('no blur'), findsOneWidget);
      expect(
        find.byWidgetPredicate((Widget widget) => widget is BackdropFilter),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps a real backdrop filter on chrome surfaces',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GlassContainer(
            surface: AuraGlassSurface.chrome,
            child: Text('frosted chrome'),
          ),
        ),
      ));

      expect(
        find.byWidgetPredicate((Widget widget) => widget is BackdropFilter),
        findsOneWidget,
      );
    });

    testWidgets('static surfaces avoid implicit animation layers',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GlassContainer(
            blur: 0,
            child: Text('static card'),
          ),
        ),
      ));

      expect(find.byType(AnimatedContainer), findsNothing);
      expect(find.byType(AnimatedScale), findsNothing);
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets('interactive surfaces keep their press affordances',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: GlassContainer(
            onTap: () {},
            child: const Text('interactive card'),
          ),
        ),
      ));

      expect(find.byType(AnimatedContainer), findsNWidgets(2));
      expect(find.byType(AnimatedScale), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
    });
  });

  group('GlassCard and GlassStatusBadge', () {
    testWidgets('compose their content', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: Column(
            children: <Widget>[
              GlassCard(child: Text('card body')),
              GlassStatusBadge(label: 'ONLINE'),
            ],
          ),
        ),
      ));

      expect(find.text('card body'), findsOneWidget);
      expect(find.text('ONLINE'), findsOneWidget);
    });
  });

  group('GlassDialog', () {
    testWidgets('shows dialog content', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showGlassDialog<void>(
                context: tester.element(find.byType(ElevatedButton)),
                child: const Text('dialog body'),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('dialog body'), findsOneWidget);
    });
  });

  group('GlassSectionHeader', () {
    testWidgets('renders title, eyebrow and trailing control',
        (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: GlassSectionHeader(
            eyebrow: 'SYSTEM',
            title: 'Overview',
            icon: Icons.space_dashboard_outlined,
            trailing: Icon(Icons.more_horiz_rounded),
          ),
        ),
      ));

      expect(find.text('SYSTEM'), findsOneWidget);
      expect(find.text('Overview'), findsOneWidget);
    });
  });
}
