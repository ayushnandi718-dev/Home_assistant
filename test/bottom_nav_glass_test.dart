import 'dart:io';

import 'package:aura_hub/app/app_shell.dart';
import 'package:aura_hub/app/shell/mobile_bottom_bar.dart';
import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_forui_theme.dart';
import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:aura_hub/core/theme/aura_theme.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  double keyboardInset = 0,
}) async {
  tester.view.physicalSize = const Size(384, 832);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 28, bottom: 48);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
  });

  await tester.pumpWidget(
    MediaQuery(
      data: MediaQueryData.fromView(tester.view).copyWith(
        viewInsets: EdgeInsets.only(bottom: keyboardInset),
      ),
      child: FTheme(
        data: auraForuiTheme(AuraPalette.violet),
        child: MaterialApp(
          home: Scaffold(
            body: MobileBottomBar(location: AppRoutes.dashboard),
          ),
        ),
      ),
    ),
  );
}

void main() {
  test('nav style is an opaque capsule with a faint border', () {
    final FBottomNavigationBarStyle style =
        auraForuiTheme(AuraPalette.violet).bottomNavigationBarStyle;
    final BoxDecoration decoration = style.decoration as BoxDecoration;
    final Border border = decoration.border! as Border;

    expect(
      decoration.borderRadius,
      BorderRadius.circular(AuraRadius.navCapsule),
    );
    expect(decoration.color, const Color(0xFF080C18));
    expect(decoration.color!.alpha, 255);

    // A barely visible outline around the capsule is fine; a top-only border
    // would recreate the unwanted full-width separator.
    expect(border.top, isNot(BorderSide.none));
    expect(border.bottom, isNot(BorderSide.none));
    expect(border.left, isNot(BorderSide.none));
    expect(border.right, isNot(BorderSide.none));
    expect(border.top.color.alpha, lessThanOrEqualTo(20));

    // The shadow, not the outline, provides separation from scrolling content.
    expect(decoration.boxShadow!.first.blurRadius, 24);
    expect(decoration.boxShadow!.first.offset, const Offset(0, 8));
    expect(decoration.boxShadow!.first.color.alpha, greaterThanOrEqualTo(140));

    // No extra glass blur layer is needed behind an opaque surface.
    expect(style.backgroundFilter, isNull);
  });

  testWidgets('nav geometry is unchanged and no blur layer remains',
      (WidgetTester tester) async {
    await _pumpBar(tester);

    final Finder bar = find.byType(FBottomNavigationBar);
    expect(bar, findsOneWidget);

    final Padding host = tester.widget<Padding>(
      find.ancestor(of: bar, matching: find.byType(Padding)).first,
    );
    expect(
      host.padding,
      EdgeInsets.fromLTRB(AuraSpace.md, 0, AuraSpace.md, AuraSpace.sm),
    );

    // Keep the gesture/three-button inset so the capsule never moves into the
    // system navigation area.
    final SafeArea safeArea = tester.widget<SafeArea>(
      find.ancestor(of: bar, matching: find.byType(SafeArea)).first,
    );
    expect(safeArea.top, isFalse);
    expect(safeArea.bottom, isTrue);

    expect(find.byType(BackdropFilter), findsNothing);

    for (final String label in <String>[
      'Home',
      'Devices',
      'Display',
      'Diagnostics',
      'More',
    ]) {
      expect(
          find.descendant(of: bar, matching: find.text(label)), findsOneWidget);
    }

    // No leftover parent/wrapper paints a top-only separator strip.
    expect(
      find.byWidgetPredicate((Widget widget) {
        if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) {
          return false;
        }
        final Object? border = (widget.decoration as BoxDecoration).border;
        if (border is! Border) return false;
        return border.top != BorderSide.none &&
            border.bottom == BorderSide.none &&
            border.left == BorderSide.none &&
            border.right == BorderSide.none;
      }),
      findsNothing,
    );
  });

  testWidgets('glass nav survives an open keyboard without overflow',
      (WidgetTester tester) async {
    await _pumpBar(tester, keyboardInset: 300);

    expect(find.byType(FBottomNavigationBar), findsOneWidget);
    expect(find.text('Diagnostics'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system navigation area is transparent, not a footer panel',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(384, 832);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 48);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: FTheme(
          data: auraForuiTheme(AuraPalette.violet),
          child: MaterialApp(
            theme: auraTheme(visual: AuraPalette.violet),
            home: AppShell(
              location: AppRoutes.dashboard,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final Finder overlayStyle = find.byWidgetPredicate(
      (Widget widget) =>
          widget is AnnotatedRegion<SystemUiOverlayStyle> &&
          widget.value.systemNavigationBarColor == Colors.transparent,
    );
    expect(overlayStyle, findsOneWidget);

    final AnnotatedRegion<SystemUiOverlayStyle> region =
        tester.widget<AnnotatedRegion<SystemUiOverlayStyle>>(overlayStyle);
    expect(region.value.systemNavigationBarColor, Colors.transparent);
    expect(region.value.systemNavigationBarDividerColor, Colors.transparent);
    expect(region.value.systemNavigationBarContrastEnforced, isFalse);
    expect(find.byType(FBottomNavigationBar), findsOneWidget);
  });

  testWidgets('bottom fade sits behind the floating capsule',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(384, 832);
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: 28, bottom: 48);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
    });

    await tester.pumpWidget(
      ProviderScope(
        child: FTheme(
          data: auraForuiTheme(AuraPalette.violet),
          child: MaterialApp(
            theme: auraTheme(visual: AuraPalette.violet),
            home: AppShell(
              location: AppRoutes.dashboard,
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );

    final Finder fade = find.byWidgetPredicate((Widget widget) {
      if (widget is! DecoratedBox || widget.decoration is! BoxDecoration) {
        return false;
      }
      final BoxDecoration decoration = widget.decoration as BoxDecoration;
      final Gradient? gradient = decoration.gradient;
      return gradient is LinearGradient &&
          gradient.begin == Alignment.topCenter &&
          gradient.end == Alignment.bottomCenter &&
          gradient.colors.first == Colors.transparent &&
          gradient.colors.last == AuraPalette.violet.backgroundEdge;
    });
    expect(fade, findsOneWidget);

    final IgnorePointer pointer = tester.widget<IgnorePointer>(
      find.ancestor(of: fade, matching: find.byType(IgnorePointer)).first,
    );
    expect(pointer.ignoring, isTrue);

    final Stack stack = tester.widget<Stack>(
      find.ancestor(of: fade, matching: find.byType(Stack)).first,
    );
    expect(stack.children[1], isA<Positioned>());
    expect(stack.children[2], isA<Align>());
    expect(
      stack.children.indexOf(
        stack.children.firstWhere((Widget child) => child is Align),
      ),
      greaterThan(
        stack.children.indexOf(
          stack.children.firstWhere((Widget child) => child is Positioned),
        ),
      ),
    );
  });

  testWidgets('mobile scroll areas reserve navigation clearance',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(393, 873);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AuraScrollArea(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 48),
          child: const SizedBox(height: 2000),
        ),
      ),
    );

    final SingleChildScrollView view = tester
        .widget<SingleChildScrollView>(find.byType(SingleChildScrollView));
    final EdgeInsets padding = view.padding! as EdgeInsets;
    expect(padding.left, 16);
    expect(padding.top, 24);
    expect(padding.right, 16);
    expect(padding.bottom, mobileNavFadeHeight);
  });

  test('Android themes do not paint an opaque navigation footer', () {
    const List<String> themePaths = <String>[
      'android/app/src/main/res/values/styles.xml',
      'android/app/src/main/res/values-night/styles.xml',
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ];

    for (final String path in themePaths) {
      final String theme = File(path).readAsStringSync();
      expect(
        theme,
        isNot(contains('<item name="android:navigationBarColor">#')),
        reason: '$path paints a full-width navigation footer',
      );
      expect(
        theme,
        contains(
          '<item name="android:navigationBarColor">@android:color/transparent</item>',
        ),
        reason: '$path must keep the gesture area transparent',
      );
      expect(
        theme,
        contains(
            '<item name="android:enforceNavigationBarContrast">false</item>'),
        reason: '$path must not add a contrast scrim footer',
      );
    }
  });
}
