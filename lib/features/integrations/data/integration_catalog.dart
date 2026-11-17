import 'package:aura_hub/features/integrations/domain/integration_service.dart';

/// Static catalog of services AURA Hub intends to support.
///
/// This is metadata only. It contains no credentials, no endpoints with keys,
/// and no claim that any service is connected or implemented. Adapters are
/// added one at a time later, behind the interfaces in
/// `integration_token_store.dart`.
abstract final class IntegrationCatalog {
  static const List<IntegrationDefinition> definitions =
      <IntegrationDefinition>[
    IntegrationDefinition(
      service: IntegrationService.gmail,
      summary: 'Read-only mail summaries for the private workspace.',
      scopes: <String>['gmail.readonly'],
      iconName: 'mail',
    ),
    IntegrationDefinition(
      service: IntegrationService.spotify,
      summary: 'Playback state and household music controls.',
      scopes: <String>[
        'user-read-playback-state',
        'user-modify-playback-state'
      ],
      iconName: 'music',
    ),
    IntegrationDefinition(
      service: IntegrationService.github,
      summary: 'Repository activity and pull request updates.',
      scopes: <String>['repo:read'],
      iconName: 'code',
    ),
    IntegrationDefinition(
      service: IntegrationService.googleCalendar,
      summary: 'Upcoming events for the family dashboard.',
      scopes: <String>['calendar.readonly'],
      iconName: 'calendar',
    ),
    IntegrationDefinition(
      service: IntegrationService.weather,
      summary: 'Local conditions for the family dashboard.',
      scopes: <String>['location:user-provided'],
      iconName: 'cloud',
    ),
    IntegrationDefinition(
      service: IntegrationService.tavilyResearch,
      summary: 'On-demand web research with cited results.',
      scopes: <String>['research:on-demand'],
      iconName: 'research',
    ),
  ];

  static IntegrationDefinition? definitionFor(IntegrationService service) {
    for (final IntegrationDefinition definition in definitions) {
      if (definition.service == service) return definition;
    }
    return null;
  }
}
