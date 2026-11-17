import 'package:aura_hub/features/integrations/domain/integration_service.dart';

/// Observable status of one integration. No field here implies a live account.
class IntegrationStatus {
  const IntegrationStatus({
    required this.service,
    required this.state,
    this.error,
    this.lastChecked,
  });

  final IntegrationService service;
  final IntegrationConnectionState state;
  final String? error;
  final DateTime? lastChecked;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IntegrationStatus &&
          other.service == service &&
          other.state == state &&
          other.error == error;

  @override
  int get hashCode => Object.hash(service, state, error);
}
