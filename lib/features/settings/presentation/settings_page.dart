import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/api_startup_guide.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real, persisted preferences. No placeholder content: every control here
/// immediately affects the running app and survives a restart.
class SettingsPage extends ConsumerStatefulWidget {
  const SettingsPage({super.key});

  @override
  ConsumerState<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends ConsumerState<SettingsPage> {
  late final TextEditingController _apiUrlController;
  final GlobalKey<FormFieldState<String>> _apiUrlFieldKey =
      GlobalKey<FormFieldState<String>>();
  bool _testingConnection = false;
  String? _healthMessage;
  bool? _healthSucceeded;

  @override
  void initState() {
    super.initState();
    _apiUrlController = TextEditingController(
      text: ref.read(appSettingsProvider).apiBaseUrl,
    );
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    super.dispose();
  }

  Future<void> _applyApiUrl() async {
    if (!(_apiUrlFieldKey.currentState?.validate() ?? false)) return;
    final String value = AppSettings.normaliseApiBaseUrl(
      _apiUrlController.text,
    );
    await ref.read(appSettingsProvider.notifier).update(
          ref.read(appSettingsProvider).copyWith(apiBaseUrl: value),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Telemetry API endpoint saved.')),
    );
  }

  Future<void> _testConnection() async {
    if (!(_apiUrlFieldKey.currentState?.validate() ?? false)) return;
    final String url = AppSettings.normaliseApiBaseUrl(_apiUrlController.text);
    setState(() {
      _testingConnection = true;
      _healthMessage = null;
      _healthSucceeded = null;
    });
    try {
      final ApiHealth health = await AuraApiClient(
        baseUrl: url,
        onRequest: ref.read(diagnosticsProvider.notifier).record,
        onHealth: (ApiHealth result) {
          ref.read(apiHealthProvider.notifier).record(result);
          ref.read(apiHealthHistoryProvider.notifier).record(result);
          ref.read(diagnosticEventsProvider.notifier).record(
                DiagnosticCategory.apiHealth,
                result.reachable
                    ? 'Health check succeeded in '
                        '${result.responseTime.inMilliseconds} ms.'
                    : 'Health check failed.',
                succeeded: result.reachable,
                error: result.error,
                duration: result.responseTime,
              );
        },
      ).checkHealth();
      if (!mounted) return;
      setState(() {
        _healthSucceeded = health.reachable;
        _healthMessage = '${health.service ?? 'AURA API'} responded in '
            '${health.responseTime.inMilliseconds} ms.';
      });
    } on AuraApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _healthSucceeded = false;
        _healthMessage = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _healthSucceeded = false;
        _healthMessage = 'Unexpected health check error: $error';
      });
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(appSettingsProvider);
    final ApiHealth? lastHealth = ref.watch(apiHealthProvider);
    final List<ApiHealth> healthHistory = ref.watch(apiHealthHistoryProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return AuraScrollArea(
      padding: EdgeInsets.fromLTRB(
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.lg,
        pageHorizontalPadding(MediaQuery.sizeOf(context).width),
        AuraSpace.xxl,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: AuraBreakpoints.content),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const PageHeader(
                eyebrow: 'System',
                title: 'Settings',
                description:
                    'Local preferences for telemetry transport, accessibility '
                    'and app information. Stored on this PC only.',
                icon: Icons.settings_outlined,
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'On-device preferences',
                message: 'These preferences are saved on this Windows PC. The '
                    'dashboard reads only the telemetry endpoint configured '
                    'below; no account or AURA device link exists in this '
                    'foundation build.',
                icon: Icons.privacy_tip_outlined,
                tone: AuraBannerTone.privacy,
              ),
              if (!settings.isLoopbackApi) ...<Widget>[
                const SizedBox(height: AuraSpace.md),
                const InfoBanner(
                  title: 'Non-local endpoint',
                  message: 'The telemetry endpoint is not on this machine. The '
                      'bundled API has no authentication, so only use a trusted '
                      'network. Authentication is required before exposing it '
                      'to an untrusted network.',
                  icon: Icons.warning_amber_rounded,
                  tone: AuraBannerTone.warning,
                ),
              ],
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Telemetry', style: text.titleLarge),
                    const SizedBox(height: AuraSpace.sm),
                    Text(
                      'Where the dashboard reads Windows host metrics and how '
                      'often it refreshes.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: AuraSpace.lg),
                    TextFormField(
                      key: _apiUrlFieldKey,
                      controller: _apiUrlController,
                      decoration: const InputDecoration(
                        labelText: 'Local telemetry API base URL',
                        hintText: 'http://127.0.0.1:8765',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.dns_outlined),
                      ),
                      validator: (String? value) {
                        return AppSettings.validateApiBaseUrl(value ?? '');
                      },
                    ),
                    const SizedBox(height: AuraSpace.sm),
                    Wrap(
                      alignment: WrapAlignment.end,
                      spacing: AuraSpace.sm,
                      runSpacing: AuraSpace.sm,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed:
                              _testingConnection ? null : _testConnection,
                          icon: _testingConnection
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.health_and_safety_outlined,
                                  size: 16),
                          label: Text(_testingConnection
                              ? 'Testing…'
                              : 'Test connection'),
                        ),
                        FilledButton(
                          onPressed: _applyApiUrl,
                          child: const Text('Save endpoint'),
                        ),
                      ],
                    ),
                    if (_healthMessage != null ||
                        lastHealth != null) ...<Widget>[
                      const SizedBox(height: AuraSpace.md),
                      InfoBanner(
                        title: _healthSucceeded == true
                            ? 'Telemetry API reachable'
                            : 'Telemetry API unavailable',
                        message: _healthMessage ?? 'No check has run yet.',
                        icon: _healthSucceeded == true
                            ? Icons.cloud_done_outlined
                            : Icons.cloud_off_outlined,
                        tone: _healthSucceeded == true
                            ? AuraBannerTone.info
                            : AuraBannerTone.warning,
                      ),
                      if (lastHealth != null)
                        _HealthDetails(
                          health: lastHealth,
                          lastSuccess: healthHistory
                                  .where((ApiHealth h) => h.reachable)
                                  .isEmpty
                              ? null
                              : healthHistory
                                  .firstWhere((ApiHealth h) => h.reachable),
                        ),
                      if (_healthSucceeded == false) ...<Widget>[
                        const SizedBox(height: AuraSpace.md),
                        const ApiStartupGuide(compact: true),
                      ],
                    ],
                    const SizedBox(height: AuraSpace.lg),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.sync_rounded),
                      title: const Text('Refresh interval'),
                      subtitle: const Text(
                        'How often live metrics are fetched from the local API.',
                      ),
                      trailing: DropdownButton<int>(
                        value: settings.pollingIntervalSeconds,
                        items: <DropdownMenuItem<int>>[
                          for (final int seconds
                              in AppSettings.supportedIntervals)
                            DropdownMenuItem<int>(
                              value: seconds,
                              child: Text('${seconds}s'),
                            ),
                        ],
                        onChanged: (int? value) {
                          if (value == null) return;
                          ref.read(appSettingsProvider.notifier).update(
                                settings.copyWith(
                                  pollingIntervalSeconds: value,
                                ),
                              );
                        },
                      ),
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.timeline_outlined),
                      title: const Text('Session history retention'),
                      subtitle: const Text(
                        'How long host telemetry trends stay in memory. '
                        'Nothing is persisted.',
                      ),
                      trailing: DropdownButton<int>(
                        value: settings.historyRetentionMinutes,
                        items: <DropdownMenuItem<int>>[
                          for (final int minutes
                              in AppSettings.supportedHistoryRetentionMinutes)
                            DropdownMenuItem<int>(
                              value: minutes,
                              child: Text('$minutes min'),
                            ),
                        ],
                        onChanged: (int? value) {
                          if (value == null) return;
                          ref.read(appSettingsProvider.notifier).update(
                                settings.copyWith(
                                  historyRetentionMinutes: value,
                                ),
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Accessibility', style: text.titleLarge),
                    const SizedBox(height: AuraSpace.lg),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.animation_outlined),
                      title: const Text('Reduce motion'),
                      subtitle: const Text(
                        'Disable app animations in addition to the Windows setting.',
                      ),
                      value: settings.reduceMotion,
                      onChanged: (bool value) {
                        ref.read(appSettingsProvider.notifier).update(
                              settings.copyWith(reduceMotion: value),
                            );
                      },
                    ),
                    const SizedBox(height: AuraSpace.md),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.density_medium_rounded),
                      title: const Text('Display density'),
                      subtitle: const Text('Spacing and control sizing.'),
                      trailing: SegmentedButton<AuraDensity>(
                        segments: const <ButtonSegment<AuraDensity>>[
                          ButtonSegment<AuraDensity>(
                            value: AuraDensity.comfortable,
                            label: Text('Comfortable'),
                          ),
                          ButtonSegment<AuraDensity>(
                            value: AuraDensity.compact,
                            label: Text('Compact'),
                          ),
                        ],
                        selected: <AuraDensity>{settings.density},
                        onSelectionChanged: (Set<AuraDensity> values) {
                          ref.read(appSettingsProvider.notifier).update(
                                settings.copyWith(density: values.first),
                              );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(Icons.info_outline_rounded,
                            color: AuraColors.primary),
                        const SizedBox(width: AuraSpace.sm),
                        Text('About', style: text.titleLarge),
                      ],
                    ),
                    const SizedBox(height: AuraSpace.md),
                    _AboutRow(label: 'Application', value: AppInfo.name),
                    _AboutRow(label: 'Product', value: AppInfo.product),
                    _AboutRow(
                      label: 'Version',
                      value: '${AppInfo.version} (${AppInfo.buildNumber})',
                    ),
                    _AboutRow(label: 'Developer', value: AppInfo.developer),
                    _AboutRow(label: 'Stage', value: AppInfo.phase),
                    _AboutRow(
                        label: 'Target hardware', value: AppInfo.hardware),
                    const SizedBox(height: AuraSpace.lg),
                    OutlinedButton.icon(
                      onPressed: settings.isDefault
                          ? null
                          : () =>
                              ref.read(appSettingsProvider.notifier).reset(),
                      icon: const Icon(Icons.restore_rounded, size: 16),
                      label: const Text('Restore defaults'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HealthDetails extends StatelessWidget {
  const _HealthDetails({required this.health, required this.lastSuccess});

  final ApiHealth health;
  final ApiHealth? lastSuccess;

  @override
  Widget build(BuildContext context) {
    final String checkedAt =
        health.checkedAt.toLocal().toString().substring(0, 19);
    return Padding(
      padding: const EdgeInsets.only(top: AuraSpace.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _HealthRow(
            label: 'Response time',
            value: '${health.responseTime.inMilliseconds} ms',
          ),
          _HealthRow(label: 'Checked', value: checkedAt),
          _HealthRow(
            label: 'Service',
            value: health.service ?? 'Not reported',
          ),
          _HealthRow(
            label: 'API version',
            value: health.version ?? 'Not reported',
          ),
          _HealthRow(
            label: 'Sampler',
            value: health.reachable ? health.samplerLabel : 'Unavailable',
          ),
          _HealthRow(
            label: 'Last telemetry sample',
            value: health.samplerLastSuccessAt == null
                ? 'None reported'
                : health.samplerLastSuccessAt!
                    .toLocal()
                    .toString()
                    .substring(0, 19),
          ),
          _HealthRow(
            label: 'Last successful check',
            value: lastSuccess == null
                ? 'None this session'
                : lastSuccess!.checkedAt.toLocal().toString().substring(0, 19),
          ),
          if (health.error != null)
            _HealthRow(label: 'Failure reason', value: health.error!),
        ],
      ),
    );
  }
}

class _HealthRow extends StatelessWidget {
  const _HealthRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xxs),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: text.bodySmall)),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: text.labelMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 140, child: Text(label, style: text.bodySmall)),
          Expanded(child: Text(value, style: text.bodyMedium)),
        ],
      ),
    );
  }
}
