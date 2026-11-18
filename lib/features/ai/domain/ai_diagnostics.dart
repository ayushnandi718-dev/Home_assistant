import 'package:aura_hub/features/ai/domain/ai_exceptions.dart';

/// Outcome of one recorded AI request stage.
enum AiDiagnosticOutcome { started, succeeded, failed, cancelled }

/// Structured, redacted record for one AI request lifecycle stage.
///
/// Only configuration metadata and failure metadata are allowed here. Prompts,
/// responses, keys, headers and full URLs never enter this object.
class AiDiagnosticEvent {
  const AiDiagnosticEvent({
    required this.stage,
    required this.providerId,
    required this.host,
    required this.method,
    required this.outcome,
    this.statusCode,
    this.failureKind,
    this.exceptionType,
    this.durationMs,
    this.tokensReceived,
  });

  final AiRequestStage stage;
  final String providerId;
  final String host;
  final String method;
  final AiDiagnosticOutcome outcome;
  final int? statusCode;
  final AiFailureKind? failureKind;
  final String? exceptionType;
  final int? durationMs;
  final int? tokensReceived;

  /// Fixed-shape context for the existing structured `AuraLogger`.
  ///
  /// [host] is derived from `Uri.host` by callers, so no scheme, path, query
  /// or credential can be included. Null fields are omitted rather than
  /// filled with raw exception text.
  Map<String, String> get context {
    final Map<String, String> result = <String, String>{
      'stage': stage.name,
      'providerId': providerId,
      'host': host,
      'method': method,
      'outcome': outcome.name,
    };
    if (statusCode != null) result['statusCode'] = statusCode.toString();
    if (failureKind != null) result['failureKind'] = failureKind!.name;
    if (exceptionType != null) result['exceptionType'] = exceptionType!;
    if (durationMs != null) result['durationMs'] = durationMs.toString();
    if (tokensReceived != null) {
      result['tokensReceived'] = tokensReceived.toString();
    }
    return Map<String, String>.unmodifiable(result);
  }
}

/// Sink for AI lifecycle diagnostics. Implementations must not persist secrets.
abstract class AiDiagnostics {
  const AiDiagnostics();

  void record(AiDiagnosticEvent event);
}

/// Default used in tests and when no logger is bound. Records nothing.
class NoAiDiagnostics extends AiDiagnostics {
  const NoAiDiagnostics();

  @override
  void record(AiDiagnosticEvent event) {}
}
