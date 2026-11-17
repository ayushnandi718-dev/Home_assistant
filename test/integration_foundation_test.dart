import 'package:aura_hub/core/logging/aura_log.dart';
import 'package:aura_hub/features/integrations/data/integration_catalog.dart';
import 'package:aura_hub/features/integrations/domain/integration_service.dart';
import 'package:aura_hub/features/integrations/domain/integration_status.dart';
import 'package:aura_hub/features/integrations/presentation/integration_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntegrationCatalog', () {
    test('covers every known service exactly once', () {
      expect(
        IntegrationCatalog.definitions
            .map((IntegrationDefinition d) => d.service)
            .toSet(),
        IntegrationService.values.toSet(),
      );
      expect(IntegrationCatalog.definitions.length,
          IntegrationService.values.length);
    });

    test('metadata contains no credentials', () {
      for (final IntegrationDefinition definition
          in IntegrationCatalog.definitions) {
        expect(definition.summary, isNot(contains('token')));
        expect(definition.summary, isNot(contains('secret')));
        expect(definition.scopes, isNotEmpty);
        expect(
          IntegrationCatalog.definitionFor(definition.service),
          same(definition),
        );
      }
    });

    test('private services never default to the shared scope', () {
      expect(IntegrationService.gmail.privateByDefault, isTrue);
      expect(IntegrationService.github.privateByDefault, isTrue);
      expect(IntegrationService.weather.privateByDefault, isFalse);
    });

    test('OAuth flag distinguishes key-based services', () {
      expect(IntegrationService.spotify.usesOAuth, isTrue);
      expect(IntegrationService.googleCalendar.usesOAuth, isTrue);
      expect(IntegrationService.weather.usesOAuth, isFalse);
      expect(IntegrationService.tavilyResearch.usesOAuth, isFalse);
    });
  });

  group('IntegrationStatus', () {
    test('a fresh status is explicitly disconnected', () {
      const IntegrationStatus status = IntegrationStatus(
        service: IntegrationService.gmail,
        state: IntegrationConnectionState.disconnected,
      );
      expect(status.state, IntegrationConnectionState.disconnected);
      expect(status.error, isNull);
      expect(status.lastChecked, isNull);
    });
  });

  group('IntegrationController', () {
    test('connect attempts are refused and logged, never faked', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      final IntegrationController controller =
          container.read(integrationControllerProvider);
      expect(controller.requestConnect(IntegrationService.spotify), isFalse);

      final List<AuraLogEntry> logs = container.read(auraLoggerProvider);
      expect(logs, isNotEmpty);
      expect(logs.first.category, 'integrations');
      expect(logs.first.level, AuraLogLevel.warning);
      expect(logs.first.message, contains('spotify'));
    });
  });

  group('Integration provider boundaries', () {
    test('no token store or OAuth flow is registered yet', () {
      final ProviderContainer container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(integrationTokenStoreProvider), isNull);
      expect(container.read(integrationOAuthFlowProvider), isNull);
      expect(
        container.read(integrationReadinessProvider),
        IntegrationReadiness.noAdapters,
      );

      final Map<IntegrationService, IntegrationStatus> statuses =
          container.read(integrationStatusProvider);
      expect(statuses.length, IntegrationService.values.length);
      for (final IntegrationStatus status in statuses.values) {
        expect(status.state, IntegrationConnectionState.disconnected);
      }
    });
  });
}
