import 'package:aura_hub/core/error/app_error_handler.dart';
import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class ThrowingAuraLogger extends AuraLogger {
  @override
  void error(
    String category,
    String message, {
    Map<String, String> context = const <String, String>{},
  }) {
    throw StateError('logger unavailable');
  }
}

void main() {
  test('global error handlers never throw when structured logging fails', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        auraLoggerProvider.overrideWith(
          (Ref ref) => ThrowingAuraLogger(),
        ),
      ],
    );
    addTearDown(container.dispose);

    final previousPresent = FlutterError.presentError;
    final previousFlutterOnError = FlutterError.onError;
    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    bool presented = false;

    FlutterError.presentError = (FlutterErrorDetails details) {
      presented = true;
    };
    addTearDown(() {
      FlutterError.presentError = previousPresent;
      FlutterError.onError = previousFlutterOnError;
      PlatformDispatcher.instance.onError = previousPlatformOnError;
    });

    installGlobalErrorHandling(container);

    final FlutterErrorDetails details = FlutterErrorDetails(
      exception: StateError('build failed'),
      library: 'test',
    );
    final StackTrace stack = StackTrace.current;

    expect(() => FlutterError.onError!(details), returnsNormally);
    expect(presented, isTrue,
        reason: 'Flutter must still present the original build error');
    expect(
      () => PlatformDispatcher.instance.onError!(StateError('platform'), stack),
      returnsNormally,
    );
    expect(
      () => recordZoneError(container, StateError('zone'), stack),
      returnsNormally,
    );
  });
}
