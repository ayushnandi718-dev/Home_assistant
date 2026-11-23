import 'dart:io';

import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/presentation/ayush_unlock_dialog.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryPinStore extends ProfilePinStore {
  _MemoryPinStore()
      : super(
          directory: Directory.systemTemp.createTempSync('aura_pin_dialog_'),
          iterations: 1000,
        );

  String? _pin;

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> setPin(String pin, {bool Function()? isCommitAllowed}) async {
    final String? error = ProfilePinStore.validatePin(pin);
    if (error != null) throw ArgumentError(error);
    _pin = pin;
  }

  @override
  Future<bool> verify(String pin, {bool Function()? isCommitAllowed}) async =>
      _pin == pin;
}

Future<void> _pumpHost(
  WidgetTester tester, {
  required ValueNotifier<double> keyboardInset,
  Size size = const Size(384, 832),
  double textScaleFactor = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  tester.view.padding = FakeViewPadding(top: 28, bottom: 48);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
  });

  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        profilePinStoreProvider.overrideWithValue(_MemoryPinStore()),
        ayushPinConfiguredProvider.overrideWith((Ref ref) async => false),
      ],
      child: ValueListenableBuilder<double>(
        valueListenable: keyboardInset,
        builder: (BuildContext context, double inset, Widget? child) {
          return MediaQuery(
            data: MediaQueryData.fromView(tester.view).copyWith(
              viewInsets: EdgeInsets.only(bottom: inset),
              textScaler: TextScaler.linear(textScaleFactor),
            ),
            child: MaterialApp(
              home: Scaffold(
                body: Center(
                  child: Builder(
                    builder: (BuildContext dialogContext) => FilledButton(
                      onPressed: () =>
                          showAyushUnlockDialog(context: dialogContext),
                      child: const Text('Open PIN dialog'),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open PIN dialog'));
  await _pumpTransition(tester);
  expect(find.byType(AyushUnlockDialog), findsOneWidget);
}

/// Glass surfaces can keep subtle animations alive; a bounded pump waits for
/// route and keyboard-layout transitions without depending on idle tickers.
Future<void> _pumpTransition(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pump();
}

void main() {
  for (final Size size in <Size>[
    Size(360, 800),
    Size(384, 832),
    Size(393, 873),
    Size(460, 900),
  ]) {
    testWidgets(
      'PIN setup stays usable with the numeric keyboard open at '
      '${size.width.toInt()}x${size.height.toInt()}',
      (WidgetTester tester) async {
        final ValueNotifier<double> keyboard = ValueNotifier<double>(300);
        addTearDown(keyboard.dispose);
        await _pumpHost(tester, keyboardInset: keyboard, size: size);
        await _openDialog(tester);

        expect(find.text('Create your AYUSH PIN'), findsOneWidget);
        expect(find.text('New PIN'), findsOneWidget);
        expect(find.text('Confirm PIN'), findsOneWidget);

        final Finder confirm = find.text('Confirm PIN');
        await tester.ensureVisible(confirm);
        await _pumpTransition(tester);
        expect(tester.takeException(), isNull);

        // Hide and reopen the keyboard: the dialog must resize both ways
        // without clipping the second field.
        keyboard.value = 0;
        await _pumpTransition(tester);
        expect(tester.takeException(), isNull);
        keyboard.value = 300;
        await _pumpTransition(tester);
        await tester.ensureVisible(find.text('Confirm PIN'));
        await _pumpTransition(tester);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('PIN setup survives large accessibility text with keyboard open',
      (WidgetTester tester) async {
    final ValueNotifier<double> keyboard = ValueNotifier<double>(300);
    addTearDown(keyboard.dispose);
    await _pumpHost(
      tester,
      keyboardInset: keyboard,
      size: const Size(360, 800),
      textScaleFactor: 1.3,
    );
    await _openDialog(tester);

    expect(find.text('Confirm PIN'), findsOneWidget);
    await tester.ensureVisible(find.text('Confirm PIN'));
    await _pumpTransition(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('barrier taps cannot dismiss PIN setup',
      (WidgetTester tester) async {
    final ValueNotifier<double> keyboard = ValueNotifier<double>(0);
    addTearDown(keyboard.dispose);
    await _pumpHost(
      tester,
      keyboardInset: keyboard,
      size: const Size(460, 900),
    );
    await _openDialog(tester);

    expect(find.byType(PopScope<bool>), findsOneWidget);
    await tester.tapAt(const Offset(230, 80));
    await _pumpTransition(tester);

    expect(find.byType(AyushUnlockDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('system Back cannot bypass PIN setup; Cancel still exits',
      (WidgetTester tester) async {
    final ValueNotifier<double> keyboard = ValueNotifier<double>(300);
    addTearDown(keyboard.dispose);
    await _pumpHost(tester, keyboardInset: keyboard);
    await _openDialog(tester);

    // The first Back dismisses the IME; neither Back pops the PIN gate.
    // ignore: invalid_use_of_protected_member
    await tester.binding.handlePopRoute();
    await _pumpTransition(tester);
    expect(find.byType(AyushUnlockDialog), findsOneWidget);

    // ignore: invalid_use_of_protected_member
    await tester.binding.handlePopRoute();
    await _pumpTransition(tester);
    expect(find.byType(AyushUnlockDialog), findsOneWidget);

    await tester.ensureVisible(find.text('Cancel'));
    await _pumpTransition(tester);
    await tester.tap(find.text('Cancel'));
    await _pumpTransition(tester);
    expect(find.byType(AyushUnlockDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Next moves to Confirm PIN and validation gates submission',
      (WidgetTester tester) async {
    final ValueNotifier<double> keyboard = ValueNotifier<double>(300);
    addTearDown(keyboard.dispose);
    await _pumpHost(tester, keyboardInset: keyboard);
    await _openDialog(tester);

    final Finder pinField = find.byType(TextField).at(0);
    final Finder confirmField = find.byType(TextField).at(1);
    final Finder submit = find.widgetWithText(FilledButton, 'Set PIN & unlock');

    await tester.tap(pinField);
    await tester.enterText(pinField, '4821');
    await tester.testTextInput.receiveAction(TextInputAction.next);
    await _pumpTransition(tester);

    expect(
      tester.widget<TextField>(confirmField).focusNode?.hasFocus,
      isTrue,
      reason: 'Next must move focus from New PIN to Confirm PIN',
    );
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(confirmField, '4822');
    await _pumpTransition(tester);
    expect(find.text('The two PIN entries do not match.'), findsOneWidget);
    expect(tester.widget<FilledButton>(submit).onPressed, isNull);

    await tester.enterText(confirmField, '4821');
    await _pumpTransition(tester);
    expect(find.text('The two PIN entries do not match.'), findsNothing);
    expect(tester.widget<FilledButton>(submit).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });
}
