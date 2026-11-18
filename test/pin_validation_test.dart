import 'package:aura_hub/features/profiles/data/profile_pin_store.dart';
import 'package:aura_hub/features/profiles/domain/pin_validation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  PinValidationResult check(String pin,
          {required bool needsSetup, String confirmation = ''}) =>
      PinValidation.evaluate(
        pin: pin,
        needsSetup: needsSetup,
        confirmation: confirmation,
      );

  group('PinValidation length boundaries', () {
    test('3 digits are too short', () {
      final PinValidationResult result = check('123', needsSetup: false);
      expect(result.issue, PinIssue.tooShort);
      expect(result.message, PinValidation.tooShortMessage);
      expect(result.isValid, isFalse);
      expect(ProfilePinStore.validatePin('123'), result.message);
    });

    test('4 digits are accepted', () {
      final PinValidationResult result = check('1234', needsSetup: false);
      expect(result.issue, PinIssue.none);
      expect(result.message, isNull);
      expect(result.isValid, isTrue);
      expect(ProfilePinStore.validatePin('1234'), isNull);
    });

    test('12 digits are accepted', () {
      final PinValidationResult result =
          check('123456789012', needsSetup: false);
      expect(result.issue, PinIssue.none);
      expect(result.isValid, isTrue);
      expect(ProfilePinStore.validatePin('123456789012'), isNull);
    });

    test('13 digits are too long', () {
      final PinValidationResult result =
          check('1234567890123', needsSetup: false);
      expect(result.issue, PinIssue.tooLong);
      expect(result.message, PinValidation.tooLongMessage);
      expect(ProfilePinStore.validatePin('1234567890123'), result.message);
    });
  });

  group('PinValidation character rules', () {
    test('empty input has its own message', () {
      final PinValidationResult result = check('', needsSetup: false);
      expect(result.issue, PinIssue.empty);
      expect(result.message, PinValidation.emptyMessage);
    });

    test('letters, spaces and non-ASCII digits are rejected as non-numeric',
        () {
      for (final String pin in <String>[
        '12a4',
        '12 4',
        '12-4',
        '१२३४',
      ]) {
        final PinValidationResult result = check(pin, needsSetup: false);
        expect(result.issue, PinIssue.nonNumeric, reason: pin);
        expect(result.message, PinValidation.nonNumericMessage);
        expect(ProfilePinStore.validatePin(pin), result.message);
      }
    });
  });

  group('PinValidation confirmation', () {
    test('setup requires a confirmation', () {
      final PinValidationResult result = check('4821', needsSetup: true);
      expect(result.issue, PinIssue.confirmationRequired);
      expect(result.message, PinValidation.confirmationRequiredMessage);
    });

    test('a different confirmation is reported as a mismatch', () {
      final PinValidationResult result = check(
        '4821',
        needsSetup: true,
        confirmation: '4822',
      );
      expect(result.issue, PinIssue.mismatch);
      expect(result.message, PinValidation.mismatchMessage);
    });

    test('an exact confirmation is accepted', () {
      final PinValidationResult result = check(
        '4821',
        needsSetup: true,
        confirmation: '4821',
      );
      expect(result.issue, PinIssue.none);
      expect(result.isValid, isTrue);
    });

    test('unlock does not require a confirmation', () {
      final PinValidationResult result = check('4821', needsSetup: false);
      expect(result.isValid, isTrue);
    });
  });

  test('store and UI share the same storage rules', () {
    for (final String pin in <String>[
      '',
      '123',
      '1234',
      '123456789012',
      '12a4'
    ]) {
      expect(
        ProfilePinStore.validatePin(pin),
        PinValidation.storageError(pin),
        reason: pin,
      );
    }
  });
}
