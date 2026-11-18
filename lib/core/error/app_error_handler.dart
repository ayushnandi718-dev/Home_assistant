import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Installs app-wide error capture into the structured logger.
///
/// Errors are recorded with redacted messages. The original error is still
/// presented to Flutter during development so debugging is unaffected.
///
/// Logging itself must never throw inside an error handler. During a widget
/// build, writing to a Riverpod StateNotifier trips Riverpod's debug guard and
/// would otherwise prevent Flutter from presenting the original failure.
void installGlobalErrorHandling(ProviderContainer container) {
  final AuraLogger logger = container.read(auraLoggerProvider.notifier);

  FlutterError.onError = (FlutterErrorDetails details) {
    // Present first so Flutter can recover from a failed build even if the
    // logger is unavailable or the container has already been disposed.
    FlutterError.presentError(details);
    _writeSafely(() {
      logger.error(
        'flutter',
        details.exceptionAsString(),
        context: <String, String>{
          'library': details.library ?? 'framework',
        },
      );
    });
  };

  PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
    _writeSafely(() {
      logger.error(
        'platform',
        error.toString(),
        context: <String, String>{
          'stack': stack.toString().split('\n').take(3).join(' | '),
        },
      );
    });
    return true;
  };
}

/// Records an error delivered by `runZonedGuarded` to the same logger.
void recordZoneError(
  ProviderContainer container,
  Object error,
  StackTrace stack,
) {
  _writeSafely(() {
    container.read(auraLoggerProvider.notifier).error(
      'zone',
      error.toString(),
      context: <String, String>{
        'stack': stack.toString().split('\n').take(3).join(' | '),
      },
    );
  });
}

void _writeSafely(void Function() write) {
  try {
    write();
  } catch (_) {
    // Structured logging is best-effort. Never let it replace the original
    // error or leave a partially built widget subtree on screen.
  }
}
