import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
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

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(appSettingsProvider);
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
                title: 'Local only',
                message:
                    'These preferences are saved on this Windows PC. Nothing is '
                    'sent to a backend, and there is no AURA device link in this '
                    'foundation build.',
                icon: Icons.privacy_tip_outlined,
                tone: AuraBannerTone.privacy,
              ),
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
                        final String url = (value ?? '').trim();
                        if (!url.startsWith('http://') &&
                            !url.startsWith('https://')) {
                          return 'Enter a full http:// or https:// URL.';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AuraSpace.sm),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        onPressed: _applyApiUrl,
                        child: const Text('Save endpoint'),
                      ),
                    ),
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
