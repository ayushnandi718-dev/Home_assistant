import 'package:aura_hub/features/ai/presentation/ai_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
      'AI page renders its real workspace without provider configuration',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: AiPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The routed page must never fall back to an empty body when no provider
    // is configured, the host API is offline, or consent has not been granted.
    expect(find.text('AURA Assistant'), findsOneWidget);
    expect(find.text('Where should we begin?'), findsOneWidget);
    expect(find.text('External AI requests are off'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'New chat'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is TextField &&
            (widget.decoration?.hintText ?? '').contains('Ask AURA anything'),
      ),
      findsOneWidget,
    );

    await tester.tap(find.widgetWithText(OutlinedButton, 'Provider'));
    await tester.pumpAndSettle();
    expect(find.text('Provider configuration'), findsOneWidget);
    expect(find.text('Provider management'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Cloud'), findsOneWidget);
    expect(find.widgetWithText(Chip, 'Local'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Back to chat'));
    await tester.pumpAndSettle();
    expect(find.text('Where should we begin?'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('blocked slang stays in the composer with a polite warning',
      (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: AiPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    const String slang = 'you bhenchod idiot';
    final Finder composerFinder = find.byWidgetPredicate(
      (Widget widget) =>
          widget is TextField &&
          (widget.decoration?.hintText ?? '').contains('Ask AURA anything'),
    );
    await tester.enterText(composerFinder, slang);
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Send'));
    await tester.pumpAndSettle();

    final TextField composer = tester.widget<TextField>(composerFinder);
    expect(composer.controller!.text, slang);
    expect(find.textContaining('keep AURA respectful'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
