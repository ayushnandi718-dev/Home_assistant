import 'dart:io';

import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/features/profiles/presentation/profiles_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory stand-in for the secure store.
///
/// Widget tests only need the controller's state transitions; the real
/// PBKDF2-HMAC-SHA256 file format, 600000 production iterations and legacy v1
/// migration are covered in `profile_pin_store_test.dart`. Using real dart:io
/// here leaves the busy spinner pending under the widget-test fake clock.
class _FastPinStore extends ProfilePinStore {
  _FastPinStore(Directory directory)
      : super(directory: directory, iterations: 1000);

  String? _pin;

  @override
  Future<bool> hasPin() async => _pin != null;

  @override
  Future<void> setPin(String pin) async {
    final String? error = ProfilePinStore.validatePin(pin);
    if (error != null) throw ArgumentError(error);
    _pin = pin;
  }

  @override
  Future<bool> verify(String pin) async => _pin == pin;
}

void main() {
  late Directory directory;
  late _FastPinStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('aura_pin_form_test_');
    store = _FastPinStore(directory);
  });

  tearDown(() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  Future<void> pumpProfiles(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          profilePinStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          home: Scaffold(body: ProfilesPage()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  FilledButton submitButton(WidgetTester tester) => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Set PIN & unlock'),
      );

  void setFieldText(WidgetTester tester, int index, String text) {
    final TextField field = tester.widget<TextField>(
      find.byType(TextField).at(index),
    );
    field.controller!.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  testWidgets('setup starts empty with no misleading validation error',
      (WidgetTester tester) async {
    await pumpProfiles(tester);

    expect(find.text('4-12 digits, numbers only.'), findsOneWidget);
    expect(find.text('0/12'), findsNWidgets(2));
    expect(find.text('Use 4 to 12 digits for the Ayush PIN.'), findsNothing);
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('3 digits show the short-PIN error and block submission',
      (WidgetTester tester) async {
    await pumpProfiles(tester);

    await tester.enterText(find.byType(TextField).at(0), '123');
    await tester.pumpAndSettle();

    expect(find.text('PIN must be at least 4 digits.'), findsOneWidget);
    expect(find.text('3/12'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('confirmation must match exactly before submission is allowed',
      (WidgetTester tester) async {
    await pumpProfiles(tester);

    await tester.enterText(find.byType(TextField).at(0), '4821');
    await tester.enterText(find.byType(TextField).at(1), '4822');
    await tester.pumpAndSettle();

    expect(find.text('The two PIN entries do not match.'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);

    await tester.enterText(find.byType(TextField).at(1), '4821');
    await tester.pumpAndSettle();

    expect(find.text('The two PIN entries do not match.'), findsNothing);
    expect(find.text('4/12'), findsNWidgets(2));
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('12 digits are accepted with consistent counters',
      (WidgetTester tester) async {
    await pumpProfiles(tester);

    await tester.enterText(find.byType(TextField).at(0), '123456789012');
    await tester.enterText(find.byType(TextField).at(1), '123456789012');
    await tester.pumpAndSettle();

    expect(find.text('12/12'), findsNWidgets(2));
    expect(
      find.text('Use 4 to 12 digits for the Ayush PIN.'),
      findsNothing,
    );
    expect(submitButton(tester).onPressed, isNotNull);
  });

  testWidgets('a 13-digit entry is rejected with the correct message',
      (WidgetTester tester) async {
    await pumpProfiles(tester);

    // TextField.maxLength blocks pasting a 13th character through normal
    // input, so set the controller directly to exercise the validation path.
    setFieldText(tester, 0, '1234567890123');
    await tester.pumpAndSettle();

    expect(find.text('PIN cannot be longer than 12 digits.'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('non-numeric input is rejected even if it is 12 characters',
      (WidgetTester tester) async {
    await pumpProfiles(tester);

    setFieldText(tester, 0, '12345678901a');
    await tester.pumpAndSettle();

    expect(find.text('PIN must contain digits only.'), findsOneWidget);
    expect(submitButton(tester).onPressed, isNull);
  });

  testWidgets('a valid setup unlocks AYUSH', (WidgetTester tester) async {
    await pumpProfiles(tester);

    await tester.enterText(find.byType(TextField).at(0), '4821');
    await tester.enterText(find.byType(TextField).at(1), '4821');
    await tester.pumpAndSettle();
    final Finder submit = find.widgetWithText(FilledButton, 'Set PIN & unlock');
    await tester.ensureVisible(submit);
    await tester.tap(submit);
    await tester.pumpAndSettle();

    expect(find.text('UNLOCKED'), findsOneWidget);
    expect(find.text('Lock private workspace'), findsOneWidget);
  });
}
