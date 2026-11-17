import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Installs app-wide error capture into the structured logger.
///
/// Errors are recorded with redacted messages. The original error is still
/// presented to Flutter during development so debugging is unaffected.
void installGlobalErrorHandling(ProviderContainer container) {
  final AuraLogger logger = container.read(auraLoggerProvider.notifier);

  FlutterError.onError = (FlutterErrorDetails details) {
    logger.error(
      'flutter',
      details.exceptionAsString(),
      context: <String, String>{
        'library': details.library ?? 'framework',
      },
    );
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    logger.error(
      'platform',
      error.toString(),
      context: <String, String>{
        'stack': stack.toString().split('\n').take(3).join(' | '),
      },
    );
    return true;
  };
}

/// Records an error delivered by `runZonedGuarded` to the same logger.
void recordZoneError(
  ProviderContainer container,
  Object error,
  StackTrace stack,
) {
  container.read(auraLoggerProvider.notifier).error(
    'zone',
    error.toString(),
    context: <String, String>{
      'stack': stack.toString().split('\n').take(3).join(' | '),
    },
  );
}
