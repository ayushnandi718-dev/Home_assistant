import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults are safe and local', () {
    const AppSettings settings = AppSettings.defaults;
    expect(settings.apiBaseUrl, 'http://127.0.0.1:8765');
    expect(settings.pollingIntervalSeconds, 3);
    expect(settings.pollingInterval, const Duration(seconds: 3));
    expect(settings.reduceMotion, isFalse);
    expect(settings.density, AuraDensity.comfortable);
    expect(settings.isDefault, isTrue);
  });

  test('normaliseApiBaseUrl strips trailing slashes and handles empty input',
      () {
    expect(
      AppSettings.normaliseApiBaseUrl('http://127.0.0.1:8765///'),
      'http://127.0.0.1:8765',
    );
    expect(
      AppSettings.normaliseApiBaseUrl('  http://localhost:9000  '),
      'http://localhost:9000',
    );
    expect(
      AppSettings.normaliseApiBaseUrl('   '),
      AppSettings.defaultApiBaseUrl,
    );
  });

  test('copyWith changes only the requested field', () {
    const AppSettings original = AppSettings.defaults;
    final AppSettings updated = original.copyWith(
      pollingIntervalSeconds: 5,
      reduceMotion: true,
    );
    expect(updated.apiBaseUrl, original.apiBaseUrl);
    expect(updated.pollingIntervalSeconds, 5);
    expect(updated.reduceMotion, isTrue);
    expect(updated.density, AuraDensity.comfortable);
    expect(updated.isDefault, isFalse);
    expect(original.pollingIntervalSeconds, 3, reason: 'original is immutable');
  });

  test('supported intervals include the 3 second default', () {
    expect(AppSettings.supportedIntervals, contains(3));
    for (final int seconds in AppSettings.supportedIntervals) {
      expect(seconds, greaterThan(0));
    }
  });
}
