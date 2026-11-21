import 'dart:async';

import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/services/clock_service.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/features/devices/domain/device_connection.dart';
import 'package:aura_hub/features/devices/presentation/devices_providers.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' as intl;

/// Local rendering of the saved 800 × 480 panel configuration.
///
/// It is deliberately labelled as a local preview: without an ESP32 transport
/// there is no confirmed physical-device screen to show.
class MobilePanelPreviewCard extends ConsumerStatefulWidget {
  const MobilePanelPreviewCard({super.key});

  @override
  ConsumerState<MobilePanelPreviewCard> createState() =>
      _MobilePanelPreviewCardState();
}

class _MobilePanelPreviewCardState
    extends ConsumerState<MobilePanelPreviewCard> {
  Timer? _tick;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    final AuraClock clock = ref.read(displayClockProvider);
    _now = clock.nowDeviceLocal();
    if (clock is SystemAuraClock) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (!mounted) return;
        setState(() => _now = clock.nowDeviceLocal());
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _refresh() {
    setState(() => _now = ref.read(displayClockProvider).nowDeviceLocal());
  }

  @override
  Widget build(BuildContext context) {
    final DisplayPreferences preferences =
        ref.watch(displayPreferencesProvider);
    final DashboardLayout layout = ref.watch(dashboardLayoutProvider);
    final DeviceLinkState link = ref.watch(deviceLinkProvider);
    final List<AuraDevice> devices =
        ref.watch(devicesProvider).valueOrNull ?? const <AuraDevice>[];
    final bool hasPairedPanel = link.isConnected &&
        link.deviceId != null &&
        devices.any((AuraDevice device) => device.id == link.deviceId);
    final TextTheme text = Theme.of(context).textTheme;
    final String time = intl.DateFormat('HH:mm').format(_now);
    final String date = intl.DateFormat('EEE, d MMM').format(_now);

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(Icons.preview_outlined, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text('Live panel preview', style: text.titleLarge),
              ),
              StatusPill(
                label: hasPairedPanel ? 'Local rendering' : 'No panel paired',
                color:
                    hasPairedPanel ? AuraColors.success : AuraColors.secondary,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          AspectRatio(
            aspectRatio: 800 / 480,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AuraRadius.card),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: preferences.wallpaper.gradient,
                  ),
                ),
                // Render the real 800 × 480 panel canvas, then scale it into
                // the card. The overlay is an explicit empty state whenever no
                // physical panel is paired; the saved configuration remains
                // visible underneath as a local preview.
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(
                    width: 800,
                    height: 480,
                    child: Stack(
                      children: <Widget>[
                        Padding(
                          padding: const EdgeInsets.all(AuraSpace.lg),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                time,
                                style: text.displayLarge?.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                date,
                                style: text.titleLarge?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '${preferences.wallpaper.label} · '
                                '${preferences.clockStyle.label}',
                                style: text.titleMedium?.copyWith(
                                  color: Colors.white70,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (layout.visibleConfigs.isNotEmpty)
                                Text(
                                  layout.visibleConfigs
                                      .take(3)
                                      .map((DashboardWidgetConfig config) =>
                                          config.id.name)
                                      .join(' · '),
                                  style: text.titleSmall?.copyWith(
                                    color: Colors.white54,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (!hasPairedPanel)
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.68),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: <Widget>[
                                    const Icon(Icons.tv_off_outlined,
                                        size: 46, color: Colors.white),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No panel paired',
                                      style: text.titleLarge?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Local preview only · saved settings are '
                                      'shown underneath',
                                      style: text.titleMedium?.copyWith(
                                        color: Colors.white70,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            hasPairedPanel
                ? 'Local rendering of the saved panel configuration. Physical '
                    'screen changes still need device acknowledgement.'
                : 'No panel paired. This is a local rendering of saved '
                    'settings, not a confirmed device screenshot.',
            style: text.bodySmall,
          ),
          const SizedBox(height: AuraSpace.sm),
          Wrap(
            spacing: AuraSpace.sm,
            runSpacing: AuraSpace.xs,
            children: <Widget>[
              OutlinedButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh preview'),
              ),
              OutlinedButton.icon(
                onPressed: () => context.go(AppRoutes.displayStudio),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Open Display Studio'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
