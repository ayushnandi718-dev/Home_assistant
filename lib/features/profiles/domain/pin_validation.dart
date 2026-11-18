import 'package:flutter/foundation.dart';

/// Why a PIN entry is not yet acceptable.
///
/// Keeping each failure distinct lets the UI name the real problem instead of
/// showing one generic "4 to 12 digits" message for every invalid value.
enum PinIssue {
  none,
  empty,
  nonNumeric,
  tooShort,
  tooLong,
  confirmationRequired,
  mismatch,
}

/// Result of validating the PIN form before it reaches the secure store.
@immutable
class PinValidationResult {
  const PinValidationResult(this.issue, this.message);

  final PinIssue issue;
  final String? message;

  bool get isValid => issue == PinIssue.none;
}

/// Shared PIN rules for both the UI and [ProfilePinStore].
///
/// Rules are deliberately strict: the PIN must be exactly 4-12 ASCII digits,
/// with no whitespace or separators, and setup requires an exact confirmation.
/// This never stores, logs or derives a key itself; it only decides whether an
/// entry is well formed so the KDF can be given a clean value.
abstract final class PinValidation {
  static const int minLength = 4;
  static const int maxLength = 12;

  static const String emptyMessage = 'Enter a PIN.';
  static const String nonNumericMessage = 'PIN must contain digits only.';
  static const String tooShortMessage = 'PIN must be at least 4 digits.';
  static const String tooLongMessage = 'PIN cannot be longer than 12 digits.';
  static const String confirmationRequiredMessage = 'Confirm your PIN.';
  static const String mismatchMessage = 'The two PIN entries do not match.';

  static final RegExp _nonDigit = RegExp(r'[^0-9]');

  static PinValidationResult evaluate({
    required String pin,
    required bool needsSetup,
    String confirmation = '',
  }) {
    if (pin.isEmpty) {
      return const PinValidationResult(PinIssue.empty, emptyMessage);
    }
    if (_nonDigit.hasMatch(pin)) {
      return const PinValidationResult(PinIssue.nonNumeric, nonNumericMessage);
    }
    if (pin.length < minLength) {
      return const PinValidationResult(PinIssue.tooShort, tooShortMessage);
    }
    if (pin.length > maxLength) {
      return const PinValidationResult(PinIssue.tooLong, tooLongMessage);
    }
    if (needsSetup) {
      if (confirmation.isEmpty) {
        return const PinValidationResult(
          PinIssue.confirmationRequired,
          confirmationRequiredMessage,
        );
      }
      if (confirmation != pin) {
        return const PinValidationResult(PinIssue.mismatch, mismatchMessage);
      }
    }
    return const PinValidationResult(PinIssue.none, null);
  }

  /// Validates a PIN for storage/unlock where no confirmation is involved.
  static String? storageError(String pin) =>
      evaluate(pin: pin, needsSetup: false).message;
}
