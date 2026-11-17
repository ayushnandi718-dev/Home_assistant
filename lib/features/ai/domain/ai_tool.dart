// Contract-only descriptions of model-callable tools.
//
// This file defines data shapes only. No tool is registered, exposed or
// executed anywhere in this build, and no model output is produced.

/// A declarative description of a tool a future client could advertise.
class AiToolDefinition {
  const AiToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    this.requiresConfirmation = false,
  });

  final String name;
  final String description;
  final Map<String, dynamic> inputSchema;

  /// Whether a sensitive action must get explicit user confirmation before it
  /// is ever executed by a future implementation. Sensitive actions (device
  /// control, messaging, purchases, file deletion and similar) MUST set this
  /// to true; an unconfirmed tool call must never be carried out.
  final bool requiresConfirmation;
}

/// A tool call requested by a model. Contract only; never executed here.
class AiToolCall {
  const AiToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

/// The outcome of a tool call. Contract only; no producer exists yet.
class AiToolResult {
  const AiToolResult({
    required this.callId,
    required this.ok,
    this.data,
    this.error,
  });

  final String callId;
  final bool ok;
  final Object? data;
  final String? error;

  factory AiToolResult.success(String callId, Object? data) =>
      AiToolResult(callId: callId, ok: true, data: data);

  factory AiToolResult.failure(String callId, String error) =>
      AiToolResult(callId: callId, ok: false, error: error);
}
