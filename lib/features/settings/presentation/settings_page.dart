import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/network/aura_api_client.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/telemetry/telemetry_api_models.dart';
import 'package:aura_hub/core/telemetry/telemetry_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/diagnostics/domain/diagnostic_event.dart';
import 'package:aura_hub/features/diagnostics/presentation/diagnostics_providers.dart';
import 'package:aura_hub/features/startup/presentation/startup_providers.dart';
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

  Future<void> _update(AppSettings next) =>
      ref.read(appSettingsProvider.notifier).update(next);

  /// Updates the persisted preference, then applies/reconciles the single
  /// Windows startup entry so the toggle is real and reversible.
  Future<void> _updateStartup(AppSettings next) async {
    await _update(next);
    await ref.read(startupControllerProvider.notifier).apply(next);
  }

  Future<void> _applyApiUrl() async {
    if (!(_apiUrlFieldKey.currentState?.validate() ?? false)) return;
    final String value = AppSettings.normaliseApiBaseUrl(
      _apiUrlController.text,
    );
    await _update(ref.read(appSettingsProvider).copyWith(apiBaseUrl: value));
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
    final TelemetryApiState telemetry = ref.watch(telemetryApiStateProvider);
    final StartupState startup = ref.watch(startupControllerProvider);
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
                    'Personalise AURA, control local telemetry and startup '
                    'behaviour, and adjust accessibility. Stored on this PC only.',
                icon: Icons.settings_outlined,
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'On-device preferences',
                message: 'These preferences are saved on this Windows PC. No '
                    'account is required and no telemetry is sent to any cloud '
                    'service.',
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

              // A. Appearance -------------------------------------------------
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Appearance', style: text.titleLarge),
                    const SizedBox(height: AuraSpace.sm),
                    Text(
                      'Choose the visual theme. Dark is the default and keeps '
                      'the original AURA look.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: AuraSpace.md),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.brightness_6_outlined),
                      title: const Text('Theme'),
                      subtitle: const Text(
                        'System follows your Windows appearance setting.',
                      ),
                      trailing: DropdownButton<AuraThemeMode>(
                        value: settings.themeMode,
                        items: <DropdownMenuItem<AuraThemeMode>>[
                          for (final AuraThemeMode mode in AuraThemeMode.values)
                            DropdownMenuItem<AuraThemeMode>(
                              value: mode,
                              child: Text(mode.label),
                            ),
                        ],
                        onChanged: (AuraThemeMode? value) {
                          if (value == null) return;
                          _update(settings.copyWith(themeMode: value));
                        },
                      ),
                    ),
                    const SizedBox(height: AuraSpace.md),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.animation_outlined),
                      title: const Text('Reduce motion'),
                      subtitle: const Text(
                        'Disable app animations in addition to the Windows setting.',
                      ),
                      value: settings.reduceMotion,
                      onChanged: (bool value) {
                        _update(settings.copyWith(reduceMotion: value));
                      },
                    ),
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
                          _update(settings.copyWith(density: values.first));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),

              // B. Language ----------------------------------------------------
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Language', style: text.titleLarge),
                    const SizedBox(height: AuraSpace.sm),
                    Text(
                      'Your application language preference is saved and applied '
                      'to the app locale where the platform supports it.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: AuraSpace.md),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.translate_outlined),
                      title: const Text('Application language'),
                      subtitle: const Text(
                        'Auto follows the Windows display language.',
                      ),
                      trailing: DropdownButton<AuraLanguage>(
                        value: settings.language,
                        items: <DropdownMenuItem<AuraLanguage>>[
                          for (final AuraLanguage language
                              in AuraLanguage.values)
                            DropdownMenuItem<AuraLanguage>(
                              value: language,
                              child: Text(language.label),
                            ),
                        ],
                        onChanged: (AuraLanguage? value) {
                          if (value == null) return;
                          _update(settings.copyWith(language: value));
                        },
                      ),
                    ),
                    const InfoBanner(
                      title: 'Translation status',
                      message: 'The interface is currently English-only. This '
                          'selection is remembered and applied to the app locale, '
                          'but Hindi and Bengali UI translations are not included '
                          'yet. AI response language is a separate preference and '
                          'is unaffected by this setting.',
                      icon: Icons.info_outline_rounded,
                      tone: AuraBannerTone.info,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),

              // C. Telemetry ---------------------------------------------------
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
                    const SizedBox(height: AuraSpace.md),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.monitor_heart_outlined),
                      title: const Text('Local telemetry'),
                      subtitle: const Text(
                        'When off, the AURA-owned sampler stops collecting '
                        'system metrics. No cloud upload exists.',
                      ),
                      value: settings.telemetryEnabled,
                      onChanged: (bool value) {
                        _update(settings.copyWith(telemetryEnabled: value));
                      },
                    ),
                    _TelemetryStatus(
                      state: telemetry,
                      lastSuccessAt: healthHistory
                              .where((ApiHealth h) => h.reachable)
                              .isEmpty
                          ? null
                          : healthHistory
                              .firstWhere((ApiHealth h) => h.reachable)
                              .samplerLastSuccessAt,
                      enabled: settings.telemetryEnabled,
                    ),
                    const SizedBox(height: AuraSpace.sm),
                    Wrap(
                      spacing: AuraSpace.sm,
                      runSpacing: AuraSpace.sm,
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: settings.telemetryEnabled
                              ? () => ref
                                  .read(telemetryApiServiceProvider.notifier)
                                  .restart()
                              : null,
                          icon: const Icon(Icons.restart_alt_rounded, size: 16),
                          label: const Text('Restart service'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AuraSpace.md),
                    const InfoBanner(
                      title: 'What is measured',
                      message: 'CPU usage, memory, disk, network I/O, battery '
                          'and running processes are read locally from the Windows '
                          'host API. Values stay on this PC and are never '
                          'transmitted to an external service.',
                      icon: Icons.local_laundry_service_outlined,
                      tone: AuraBannerTone.info,
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
                          _update(
                              settings.copyWith(pollingIntervalSeconds: value));
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
                          _update(settings.copyWith(
                              historyRetentionMinutes: value));
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),

              // D. Startup & behaviour ----------------------------------------
              SurfaceCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('Startup & behaviour', style: text.titleLarge),
                    const SizedBox(height: AuraSpace.sm),
                    Text(
                      'Control how AURA starts with Windows. Startup uses a '
                      'reversible per-user entry and never stores your PIN.',
                      style: text.bodyMedium,
                    ),
                    const SizedBox(height: AuraSpace.md),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.power_settings_new_outlined),
                      title: const Text('Launch AURA when Windows starts'),
                      subtitle: const Text(
                        'Adds or removes one CurrentUser startup entry.',
                      ),
                      value: settings.launchAtStartup,
                      onChanged: (bool value) {
                        _updateStartup(
                          settings.copyWith(launchAtStartup: value),
                        );
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.minimize_outlined),
                      title: const Text('Start minimized'),
                      subtitle: const Text(
                        'Minimize the AURA window when it launches.',
                      ),
                      value: settings.startMinimized,
                      onChanged: (bool value) {
                        _updateStartup(
                            settings.copyWith(startMinimized: value));
                      },
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      secondary: const Icon(Icons.person_search_outlined),
                      title: const Text('Remember last active profile'),
                      subtitle: const Text(
                        'AYUSH will still require its PIN after every restart.',
                      ),
                      value: settings.rememberLastProfile,
                      onChanged: (bool value) {
                        _update(settings.copyWith(
                          rememberLastProfile: value,
                          clearLastActiveProfile: !value,
                        ));
                      },
                    ),
                    if (startup.applying)
                      const Padding(
                        padding: EdgeInsets.only(top: AuraSpace.sm),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (startup.result != null &&
                        !startup.result!.ok &&
                        settings.launchAtStartup)
                      Padding(
                        padding: const EdgeInsets.only(top: AuraSpace.md),
                        child: InfoBanner(
                          title: 'Windows startup unavailable',
                          message: startup.result!.error ??
                              'The startup setting could not be applied.',
                          icon: Icons.warning_amber_rounded,
                          tone: AuraBannerTone.warning,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AuraSpace.lg),

              // About ----------------------------------------------------------
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

class _TelemetryStatus extends StatelessWidget {
  const _TelemetryStatus({
    required this.state,
    required this.lastSuccessAt,
    required this.enabled,
  });

  final TelemetryApiState state;
  final DateTime? lastSuccessAt;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool disabled = !enabled || state.issue == TelemetryApiIssue.disabled;
    final Color color = disabled
        ? AuraColors.textSecondary
        : state.isOnline
            ? AuraColors.success
            : AuraColors.warning;
    final String statusLabel = disabled ? 'Disabled' : state.status.label;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AuraSpace.md),
      decoration: BoxDecoration(
        color: AuraColors.card.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(AuraRadius.control),
        border: Border.all(color: AuraColors.border.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.circle, size: 9, color: color),
              const SizedBox(width: AuraSpace.xs),
              Text('Service: $statusLabel',
                  style: text.titleSmall?.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: AuraSpace.xxs),
          Text(
              disabled
                  ? 'No system metrics are being collected.'
                  : state.message,
              style: text.bodySmall),
          const SizedBox(height: AuraSpace.xxs),
          _HealthRow(
            label: 'Last successful sample',
            value: lastSuccessAt == null
                ? 'None yet'
                : lastSuccessAt!.toLocal().toString().substring(0, 19),
          ),
          _HealthRow(
            label: 'Last status check',
            value: state.lastCheckedAt == null
                ? 'Not checked'
                : state.lastCheckedAt!.toLocal().toString().substring(0, 19),
          ),
        ],
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
