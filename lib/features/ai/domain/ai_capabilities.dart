import 'package:aura_hub/features/ai/domain/ai_tool.dart';

/// Declares what AURA Assistant can actually do in this build.
///
/// Tool support is deliberately declaration-only: no tool is registered, and
/// model-requested tool calls are never executed.
abstract final class AiAssistantCapabilities {
  static const bool streaming = true;
  static const bool persistentHistory = true;
  static const bool multilingual = true;
  static const bool externalProviders = true;
  static const bool toolExecution = false;
  static const bool autonomousActions = false;

  static const List<String> languages = <String>['en', 'bn', 'hi'];
}

/// Permission level required by a future tool.
enum AiToolPermission {
  /// Not registered; the model cannot use it.
  none,

  /// Explicit per-call confirmation would be required before execution.
  explicitConfirmation,
}

/// Immutable declaration of a future tool.
///
/// There is no executor here on purpose. Adding a tool must be a separate,
/// reviewed change that supplies a controlled executor and permission check.
class AiToolRegistration {
  const AiToolRegistration({
    required this.definition,
    required this.permission,
  });

  final AiToolDefinition definition;
  final AiToolPermission permission;
}

/// Empty-by-default registry extension point.
class AiToolRegistry {
  const AiToolRegistry({this.registrations = const <AiToolRegistration>[]});

  final List<AiToolRegistration> registrations;

  static const AiToolRegistry empty = AiToolRegistry();

  bool get isEmpty => registrations.isEmpty;

  List<AiToolDefinition> get definitions => registrations
      .map((AiToolRegistration registration) => registration.definition)
      .toList(growable: false);

  AiToolRegistration? find(String name) {
    for (final AiToolRegistration registration in registrations) {
      if (registration.definition.name == name) return registration;
    }
    return null;
  }
}
