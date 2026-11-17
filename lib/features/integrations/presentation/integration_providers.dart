import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/integrations/data/integration_catalog.dart';
import 'package:aura_hub/features/integrations/domain/integration_service.dart';
import 'package:aura_hub/features/integrations/domain/integration_status.dart';
import 'package:aura_hub/features/integrations/domain/integration_token_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether any real adapter exists. There is deliberately no adapter yet.
enum IntegrationReadiness { noAdapters, adaptersAvailable }

/// Static, credential-free catalog of known services.
final Provider<List<IntegrationDefinition>> integrationCatalogProvider =
    Provider<List<IntegrationDefinition>>(
  (Ref ref) => IntegrationCatalog.definitions,
);

/// Every service reports an explicit disconnected state. No sample accounts,
/// no cached tokens, no optimistic "connected" values.
final Provider<Map<IntegrationService, IntegrationStatus>>
    integrationStatusProvider =
    Provider<Map<IntegrationService, IntegrationStatus>>((Ref ref) {
  return <IntegrationService, IntegrationStatus>{
    for (final IntegrationService service in IntegrationService.values)
      service: IntegrationStatus(
        service: service,
        state: IntegrationConnectionState.disconnected,
      ),
  };
});

/// Security boundaries. Null means no implementation has been provided; the UI
/// must present these as unavailable rather than inventing a connect flow.
final Provider<IntegrationTokenStore?> integrationTokenStoreProvider =
    Provider<IntegrationTokenStore?>((Ref ref) => null);

final Provider<IntegrationOAuthFlow?> integrationOAuthFlowProvider =
    Provider<IntegrationOAuthFlow?>((Ref ref) => null);

final Provider<IntegrationReadiness> integrationReadinessProvider =
    Provider<IntegrationReadiness>((Ref ref) {
  // Flip only when a real adapter and a secure token store are registered.
  return IntegrationReadiness.noAdapters;
});

/// Handles user attempts to connect a service honestly.
///
/// Because no adapter exists, every request is refused and logged. This gives
/// the UI a single, testable path for graceful failure instead of a fake
/// "Connecting..." animation.
class IntegrationController {
  IntegrationController(this._ref);

  final Ref _ref;

  bool requestConnect(IntegrationService service) {
    _ref.read(auraLoggerProvider.notifier).warning(
          'integrations',
          'Connect requested for ${service.name} but no adapter is available.',
        );
    return false;
  }
}

final Provider<IntegrationController> integrationControllerProvider =
    Provider<IntegrationController>(
  (Ref ref) => IntegrationController(ref),
);
