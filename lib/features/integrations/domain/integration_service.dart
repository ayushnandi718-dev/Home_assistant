/// Known third-party services AURA Hub may support in the future.
///
/// Listing a service here is NOT a claim that it is connected, configured or
/// even implemented. It is a stable identifier used by definitions, storage
/// scopes and future adapters.
enum IntegrationService {
  gmail,
  spotify,
  github,
  googleCalendar,
  weather,
  tavilyResearch,
}

/// Honest connection state for an integration.
enum IntegrationConnectionState {
  /// No account is linked. This is the state for every service today.
  disconnected,

  /// An adapter exists but cannot be used (missing configuration/dependency).
  unavailable,

  /// A concrete adapter reported a failure.
  error,
}

extension IntegrationServiceX on IntegrationService {
  String get label {
    switch (this) {
      case IntegrationService.gmail:
        return 'Gmail';
      case IntegrationService.spotify:
        return 'Spotify';
      case IntegrationService.github:
        return 'GitHub';
      case IntegrationService.googleCalendar:
        return 'Google Calendar';
      case IntegrationService.weather:
        return 'Weather';
      case IntegrationService.tavilyResearch:
        return 'Tavily Research';
    }
  }

  String get storageScope => name;

  /// Whether this service is expected to use OAuth when an adapter is added.
  /// Weather and research typically use API keys instead.
  bool get usesOAuth =>
      this != IntegrationService.weather &&
      this != IntegrationService.tavilyResearch;

  /// Which workspace a future token belongs to. Private services never fall
  /// back to the shared FAMILY scope.
  bool get privateByDefault => this != IntegrationService.weather;
}

/// Immutable description of a supported integration capability.
class IntegrationDefinition {
  const IntegrationDefinition({
    required this.service,
    required this.summary,
    required this.scopes,
    required this.iconName,
  });

  final IntegrationService service;
  final String summary;
  final List<String> scopes;

  /// Icon token name; the UI maps this to an IconData so domain stays pure.
  final String iconName;

  String get label => service.label;
}
