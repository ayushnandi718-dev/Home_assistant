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

  test('isLoopbackApi distinguishes local endpoints from remote hosts', () {
    expect(AppSettings.defaults.isLoopbackApi, isTrue);
    expect(
      AppSettings.defaults
          .copyWith(apiBaseUrl: 'http://localhost:9000')
          .isLoopbackApi,
      isTrue,
    );
    expect(
      AppSettings.defaults
          .copyWith(apiBaseUrl: 'https://telemetry.example.test')
          .isLoopbackApi,
      isFalse,
    );
    expect(
      AppSettings.defaults
          .copyWith(apiBaseUrl: 'http://192.168.1.50:8765')
          .isLoopbackApi,
      isFalse,
    );
  });

  test('supported intervals include the 3 second default', () {
    expect(AppSettings.supportedIntervals, contains(3));
    for (final int seconds in AppSettings.supportedIntervals) {
      expect(seconds, greaterThan(0));
    }
  });

  test('telemetry URL validation accepts endpoints and rejects unsafe forms',
      () {
    expect(AppSettings.validateApiBaseUrl('http://127.0.0.1:8765'), isNull);
    expect(AppSettings.validateApiBaseUrl('https://telemetry.example.test'),
        isNull);
    expect(AppSettings.validateApiBaseUrl('127.0.0.1:8765'), isNotNull);
    expect(AppSettings.validateApiBaseUrl('http:///missing-host'), isNotNull);
    expect(AppSettings.validateApiBaseUrl('http://user:pass@host'), isNotNull);
    expect(
        AppSettings.validateApiBaseUrl('http://host/?token=value'), isNotNull);
  });

  test('history retention defaults to 30 minutes and round-trips copyWith', () {
    expect(AppSettings.defaults.historyRetentionMinutes, 30);
    expect(AppSettings.defaults.historyRetention, const Duration(minutes: 30));
    expect(
      AppSettings.supportedHistoryRetentionMinutes,
      contains(AppSettings.defaultHistoryRetentionMinutes),
    );
    final AppSettings updated =
        AppSettings.defaults.copyWith(historyRetentionMinutes: 60);
    expect(updated.historyRetention, const Duration(minutes: 60));
    expect(updated.apiBaseUrl, AppSettings.defaults.apiBaseUrl);
    expect(updated.isDefault, isFalse);
  });

  group('validateApiBaseUrl edge cases', () {
    test('rejects unsupported schemes, malformed URLs and invalid ports', () {
      expect(AppSettings.validateApiBaseUrl('ftp://127.0.0.1'), isNotNull);
      expect(AppSettings.validateApiBaseUrl('http://'), isNotNull);
      expect(AppSettings.validateApiBaseUrl('not a url'), isNotNull);
      expect(AppSettings.validateApiBaseUrl('http://127.0.0.1:0'), isNotNull);
      expect(
        AppSettings.validateApiBaseUrl('http://127.0.0.1:70000'),
        isNotNull,
      );
    });

    test('rejects fragments and extra base paths', () {
      expect(
        AppSettings.validateApiBaseUrl('http://127.0.0.1:8765/#private'),
        isNotNull,
      );
      expect(
        AppSettings.validateApiBaseUrl('http://127.0.0.1:8765/api'),
        isNotNull,
      );
    });
  });
}
