import 'package:aura_hub/features/ai/domain/ai_context.dart';

/// Cooperative cancellation handle for an AI request.
///
/// The UI calls [cancel] when the user stops generation or leaves a protected
/// profile. Adapters must check [isCancelled] while streaming and the HTTP
/// transport aborts the underlying request when possible.
class AiCancelToken {
  final List<void Function()> _listeners = <void Function()>[];

  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    for (final void Function() listener
        in List<void Function()>.from(_listeners)) {
      listener();
    }
  }

  void addListener(void Function() listener) {
    if (_isCancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) => _listeners.remove(listener);
}

/// Per-request material that must never be persisted or logged.
class AiRequestContext {
  const AiRequestContext({
    this.apiKey,
    this.cancelToken,
    this.timeout = const Duration(seconds: 45),
    this.assembledContext,
  });

  /// Transient provider credential. Null for local endpoints that need none.
  /// Never include this value in an exception, log, diagnostic or JSON store.
  final String? apiKey;

  final AiCancelToken? cancelToken;
  final Duration timeout;

  /// Bounded, profile-safe context prepared before the request. Contains no
  /// credentials and is never persisted back into conversation history.
  final AiAssembledContext? assembledContext;

  /// Safe summary for diagnostics; deliberately omits the key and all context
  /// text. Only counts and timing metadata may be exposed here.
  Map<String, String> get safeContext => <String, String>{
        'hasApiKey': (apiKey != null && apiKey!.isNotEmpty).toString(),
        'timeoutMs': timeout.inMilliseconds.toString(),
        'contextMessages': (assembledContext?.messages.length ?? 0).toString(),
      };
}
