import 'dart:async';
import 'dart:math' as math;

import 'package:aura_hub/core/services/clock_service.dart';
import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/dashboard_widget_studio_dialog.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:aura_hub/features/display/presentation/widgets/wallpaper_widgets.dart';
import 'package:aura_hub/features/profiles/domain/aura_profile.dart';
import 'package:aura_hub/features/profiles/presentation/profile_providers.dart';
import 'package:aura_hub/shared/widgets/aura_scroll_area.dart';
import 'package:aura_hub/shared/widgets/capability_status_key.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:aura_hub/shared/widgets/info_banner.dart';
import 'package:aura_hub/shared/widgets/page_header.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

/// Below this width the hardware-status pill and the save-state label are
/// stacked instead of competing for the same row, matching the responsive rows
/// in Voice & Audio and Settings.
const double _kStackBreakpoint = 620;

/// Software-side Display Studio.
///
/// Every control either changes the persisted workspace preference or the
/// Flutter-drawn preview. No command is sent to a device: physical brightness,
/// timeout, sleep and rotation remain hardware-dependent until a real AURA
/// transport exists.
class DisplayStudioPage extends ConsumerWidget {
  const DisplayStudioPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final DisplayPreferences preferences =
        ref.watch(displayPreferencesProvider);
    final AuraClock clock = ref.watch(displayClockProvider);
    final DisplayPreferencesController controller =
        ref.read(activeDisplayPreferencesControllerProvider);
    final AppSettings settings = ref.watch(appSettingsProvider);
    final AuraProfile profile = ref.watch(activeProfileProvider);
    final DashboardLayout dashboardLayout = ref.watch(dashboardLayoutProvider);
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
              PageHeader(
                eyebrow: 'Experience',
                title: 'Display Studio',
                description:
                    'Shape what appears on the AURA panel: brightness, '
                    'widgets, wallpaper and sleep behaviour. Changes here are '
                    'saved for the ${profile.label} workspace.',
                icon: Icons.palette_outlined,
                accent: AuraColors.primary,
                trailing: const StatusPill(
                  label: 'Preview only',
                  color: AuraColors.secondary,
                ),
              ),
              const SizedBox(height: AuraSpace.lg),
              const InfoBanner(
                title: 'Local preview — no device commands',
                message: 'The panel on the right is drawn by Flutter. It shows '
                    'your saved choices but cannot change physical brightness, '
                    'sleep timing or orientation until an AURA device transport '
                    'is implemented.',
                icon: Icons.preview_outlined,
                tone: AuraBannerTone.privacy,
              ),
              const SizedBox(height: AuraSpace.md),
              const CapabilityStatusKey(),
              const SizedBox(height: AuraSpace.lg),
              LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final bool wide = constraints.maxWidth >= 1040;
                  final Widget controls = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      _BrightnessCard(
                        preferences: preferences,
                        controller: controller,
                      ),
                      const SizedBox(height: AuraSpace.lg),
                      _ThemeCard(
                        preferences: preferences,
                        controller: controller,
                        settings: settings,
                        ref: ref,
                      ),
                      const SizedBox(height: AuraSpace.lg),
                      _WidgetCard(layout: dashboardLayout),
                      const SizedBox(height: AuraSpace.lg),
                      _OrientationCard(
                        preferences: preferences,
                        controller: controller,
                      ),
                    ],
                  );
                  final Widget preview = _PanelPreview(
                    preferences: preferences,
                    clock: clock,
                  );
                  if (wide) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Expanded(child: controls),
                        const SizedBox(width: AuraSpace.lg),
                        SizedBox(width: 380, child: preview),
                      ],
                    );
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      preview,
                      const SizedBox(height: AuraSpace.lg),
                      controls,
                    ],
                  );
                },
              ),
              const SizedBox(height: AuraSpace.md),
              Text(
                'Preferences are stored on this PC and are isolated per workspace.',
                style: text.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrightnessCard extends StatelessWidget {
  const _BrightnessCard({
    required this.preferences,
    required this.controller,
  });

  final DisplayPreferences preferences;
  final DisplayPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final SleepSchedule sleep = preferences.sleepSchedule;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.brightness_6_outlined, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text(
                  'Brightness, timeout & sleep',
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Configuration is saved and applied to the local preview. '
            'A physical panel cannot receive these values yet.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          Row(
            children: <Widget>[
              const Icon(Icons.brightness_5_outlined, size: 18),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Slider(
                  value: preferences.brightness.toDouble(),
                  min: DisplayPreferences.minBrightness.toDouble(),
                  max: DisplayPreferences.maxBrightness.toDouble(),
                  divisions: DisplayPreferences.maxBrightness -
                      DisplayPreferences.minBrightness,
                  label: '${preferences.brightness}%',
                  onChanged: (double value) => controller.update(
                    preferences.copyWith(brightness: value.round()),
                  ),
                ),
              ),
              SizedBox(
                width: 52,
                child: Text(
                  '${preferences.brightness}%',
                  textAlign: TextAlign.end,
                  style: text.labelLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.xs),
          _SettingRow(
            icon: Icons.schedule_outlined,
            title: 'Screen timeout',
            subtitle: 'Saved for the panel; not an OS display setting.',
            control: (bool stacked) => DropdownButton<ScreenTimeout>(
              isExpanded: true,
              isDense: true,
              value: preferences.screenTimeout,
              items: <DropdownMenuItem<ScreenTimeout>>[
                for (final ScreenTimeout option in ScreenTimeout.values)
                  DropdownMenuItem<ScreenTimeout>(
                    value: option,
                    child: Text(option.label),
                  ),
              ],
              onChanged: (ScreenTimeout? value) {
                if (value != null) {
                  controller.update(
                    preferences.copyWith(screenTimeout: value),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.nightlight_outlined),
            title: const Text('Sleep schedule'),
            subtitle: Text('Window: ${sleep.summary}'),
            value: sleep.enabled,
            onChanged: (bool value) => controller.update(
              preferences.copyWith(
                  sleepSchedule: sleep.copyWith(enabled: value)),
            ),
          ),
          _SettingRow(
            icon: Icons.nights_stay_outlined,
            title: 'Sleep starts',
            subtitle: 'Local time on the panel.',
            control: (bool stacked) => DropdownButton<int>(
              isExpanded: true,
              isDense: true,
              value: sleep.startMinutes,
              items: <DropdownMenuItem<int>>[
                for (int minutes = 0; minutes < 1440; minutes += 30)
                  DropdownMenuItem<int>(
                    value: minutes,
                    child: Text(SleepSchedule.formatMinutes(minutes)),
                  ),
              ],
              onChanged: (int? value) {
                if (value != null) {
                  controller.update(
                    preferences.copyWith(
                      sleepSchedule: sleep.copyWith(startMinutes: value),
                    ),
                  );
                }
              },
            ),
          ),
          _SettingRow(
            icon: Icons.wb_sunny_outlined,
            title: 'Sleep ends',
            subtitle: 'Local time on the panel.',
            control: (bool stacked) => DropdownButton<int>(
              isExpanded: true,
              isDense: true,
              value: sleep.endMinutes,
              items: <DropdownMenuItem<int>>[
                for (int minutes = 0; minutes < 1440; minutes += 30)
                  DropdownMenuItem<int>(
                    value: minutes,
                    child: Text(SleepSchedule.formatMinutes(minutes)),
                  ),
              ],
              onChanged: (int? value) {
                if (value != null) {
                  controller.update(
                    preferences.copyWith(
                      sleepSchedule: sleep.copyWith(endMinutes: value),
                    ),
                  );
                }
              },
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          const StatusPill(
            label: 'Requires AURA hardware to apply',
            color: AuraColors.warning,
            dense: true,
            showDot: false,
          ),
        ],
      ),
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.preferences,
    required this.controller,
    required this.settings,
    required this.ref,
  });

  final DisplayPreferences preferences;
  final DisplayPreferencesController controller;
  final AppSettings settings;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.wallpaper_outlined, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text(
                  'Theme, wallpaper & clock',
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'The application theme is real and shared with Settings. Panel '
            'theme, wallpaper and clock style change the preview only.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          _SettingRow(
            icon: Icons.brightness_4_outlined,
            title: 'Application theme',
            subtitle: 'Changes the whole app immediately and persists.',
            control: (bool stacked) => DropdownButton<AuraThemeMode>(
              isExpanded: true,
              isDense: true,
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
                ref
                    .read(appSettingsProvider.notifier)
                    .update(settings.copyWith(themeMode: value));
              },
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          Text('Panel theme (preview only)', style: text.titleSmall),
          const SizedBox(height: AuraSpace.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<PanelTheme>(
              segments: <ButtonSegment<PanelTheme>>[
                for (final PanelTheme theme in PanelTheme.values)
                  ButtonSegment<PanelTheme>(
                    value: theme,
                    label: Text(theme.label),
                  ),
              ],
              selected: <PanelTheme>{preferences.panelTheme},
              onSelectionChanged: (Set<PanelTheme> values) {
                if (values.isEmpty) return;
                controller.update(
                  preferences.copyWith(panelTheme: values.first),
                );
              },
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          Text('Wallpaper (preview only)', style: text.titleSmall),
          const SizedBox(height: AuraSpace.xs),
          WallpaperGrid(
            selected: preferences.wallpaper,
            accent: preferences.panelTheme.accent,
            onSelected: (PanelWallpaper w) =>
                controller.update(preferences.copyWith(wallpaper: w)),
          ),
          const SizedBox(height: AuraSpace.md),
          Text('Clock style (preview only)', style: text.titleSmall),
          const SizedBox(height: AuraSpace.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<ClockStyle>(
              segments: <ButtonSegment<ClockStyle>>[
                for (final ClockStyle style in ClockStyle.values)
                  ButtonSegment<ClockStyle>(
                    value: style,
                    label: Text(style.label),
                  ),
              ],
              selected: <ClockStyle>{preferences.clockStyle},
              onSelectionChanged: (Set<ClockStyle> values) {
                if (values.isEmpty) return;
                controller
                    .update(preferences.copyWith(clockStyle: values.first));
              },
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          Text('Watch face (preview only)', style: text.titleSmall),
          const SizedBox(height: AuraSpace.xs),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<PanelWatchFace>(
              segments: <ButtonSegment<PanelWatchFace>>[
                for (final PanelWatchFace face in PanelWatchFace.values)
                  ButtonSegment<PanelWatchFace>(
                    value: face,
                    label: Text(face.label),
                  ),
              ],
              selected: <PanelWatchFace>{preferences.watchFace},
              onSelectionChanged: (Set<PanelWatchFace> values) {
                if (values.isEmpty) return;
                controller.update(
                  preferences.copyWith(watchFace: values.first),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WidgetCard extends StatelessWidget {
  const _WidgetCard({required this.layout});

  final DashboardLayout layout;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    // Only the existing dashboard layout is read here: this page never creates
    // a second persistence path for widget visibility or ordering.
    final int visibleCount = layout.visibleConfigs.length;
    final int totalCount = layout.widgets.length;
    final String labels = layout.visibleConfigs
        .map((DashboardWidgetConfig item) => item.id.label)
        .join(' · ');

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.widgets_outlined, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text(
                  'Dashboard widgets',
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Open the existing widget studio to hide, resize and reorder the '
            'widgets on the active workspace dashboard. Every edit persists to '
            'that workspace only.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            '$visibleCount of $totalCount widgets visible. $labels',
            style: text.bodySmall,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: AuraSpace.md),
          Wrap(
            spacing: AuraSpace.sm,
            runSpacing: AuraSpace.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              FilledButton.icon(
                onPressed: () => showGlassDialog<void>(
                  context: context,
                  child: const DashboardWidgetStudioDialog(),
                ),
                icon: const Icon(Icons.tune_rounded, size: 16),
                label: const Text('Open widget studio'),
              ),
              const StatusPill(
                label: 'Available on this computer',
                color: AuraColors.success,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          const InfoBanner(
            title: 'Not every planned widget exists',
            message: 'Clock, weather and calendar panels are not implemented '
                'dashboard widgets. The studio edits the real widgets listed in '
                'the current dashboard only; no placeholder widget is shown.',
            icon: Icons.info_outline_rounded,
            tone: AuraBannerTone.info,
          ),
        ],
      ),
    );
  }
}

class _OrientationCard extends StatelessWidget {
  const _OrientationCard({
    required this.preferences,
    required this.controller,
  });

  final DisplayPreferences preferences;
  final DisplayPreferencesController controller;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.screen_rotation_outlined, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Text(
                  'Orientation & saved state',
                  style: text.titleLarge,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.sm),
          Text(
            'Choose how the simulated panel is shaped. Rotating a physical '
            'ESP32-S3 display needs a real device transport and is not possible '
            'from this build.',
            style: text.bodyMedium,
          ),
          const SizedBox(height: AuraSpace.md),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: SegmentedButton<PanelOrientation>(
              segments: <ButtonSegment<PanelOrientation>>[
                for (final PanelOrientation option in PanelOrientation.values)
                  ButtonSegment<PanelOrientation>(
                    value: option,
                    label: Text(option.label),
                  ),
              ],
              selected: <PanelOrientation>{preferences.orientation},
              onSelectionChanged: (Set<PanelOrientation> values) {
                if (values.isEmpty) return;
                controller.update(
                  preferences.copyWith(orientation: values.first),
                );
              },
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              const StatusPill pill = StatusPill(
                label: 'Requires AURA hardware to apply',
                color: AuraColors.warning,
                dense: true,
              );
              final Widget saveState = ValueListenableBuilder<DisplaySaveState>(
                valueListenable: controller.saveState,
                builder: (BuildContext context, DisplaySaveState state, _) {
                  return Text(
                    state.label,
                    textAlign: constraints.maxWidth < _kStackBreakpoint
                        ? TextAlign.start
                        : TextAlign.end,
                    style: text.bodySmall?.copyWith(
                      color: state == DisplaySaveState.failed
                          ? AuraColors.danger
                          : AuraColors.textSecondary,
                    ),
                  );
                },
              );
              if (constraints.maxWidth < _kStackBreakpoint) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    pill,
                    const SizedBox(height: AuraSpace.xs),
                    saveState,
                  ],
                );
              }
              return Row(
                children: <Widget>[
                  pill,
                  const SizedBox(width: AuraSpace.sm),
                  Expanded(child: saveState),
                ],
              );
            },
          ),
          const SizedBox(height: AuraSpace.xs),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => controller.reset(),
              icon: const Icon(Icons.restore_rounded, size: 16),
              label: const Text('Reset workspace preview settings'),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelPreview extends StatefulWidget {
  const _PanelPreview({
    required this.preferences,
    this.clock = SystemAuraClock.instance,
  });

  final DisplayPreferences preferences;
  final AuraClock clock;

  @override
  State<_PanelPreview> createState() => _PanelPreviewState();
}

class _PanelPreviewState extends State<_PanelPreview>
    with SingleTickerProviderStateMixin {
  late DateTime _now;
  AnimationController? _sweep;
  Timer? _tick;

  DisplayPreferences get preferences => widget.preferences;
  AuraClock get clock => widget.clock;
  bool get _isLive => clock is SystemAuraClock;

  String get _timeLabel => intl.DateFormat('HH:mm:ss').format(_now);
  String get _shortTimeLabel => intl.DateFormat('HH:mm').format(_now);
  String get _dateLabel => intl.DateFormat('EEE, d MMM yyyy').format(_now);

  String get _zoneLabel {
    final Duration offset = clock.deviceUtcOffset;
    final bool negative = offset.isNegative;
    final Duration absolute = negative ? -offset : offset;
    final String hours = absolute.inHours.toString().padLeft(2, '0');
    final String minutes =
        (absolute.inMinutes.remainder(60)).toString().padLeft(2, '0');
    return '${clock.deviceTimeZoneName} · UTC${negative ? '-' : '+'}$hours:$minutes';
  }

  @override
  void initState() {
    super.initState();
    _now = clock.nowDeviceLocal();
    if (_isLive) _startLiveTicks();
  }

  @override
  void didUpdateWidget(covariant _PanelPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.clock == oldWidget.clock) return;
    _stopLiveTicks();
    _now = clock.nowDeviceLocal();
    if (_isLive) _startLiveTicks();
  }

  void _startLiveTicks() {
    _sweep = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..repeat();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = clock.nowDeviceLocal());
    });
  }

  void _stopLiveTicks() {
    _tick?.cancel();
    _tick = null;
    _sweep?.dispose();
    _sweep = null;
  }

  @override
  void dispose() {
    _stopLiveTicks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final bool landscape =
        preferences.orientation == PanelOrientation.landscape;
    final Color accent = preferences.panelTheme.accent;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.preview_outlined, color: accent),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                  child: Text('Local panel preview', style: text.titleLarge)),
              const StatusPill(
                label: 'Preview only',
                color: AuraColors.secondary,
                dense: true,
                showDot: false,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          Center(
            child: AspectRatio(
              aspectRatio: landscape ? kPanelAspect : 1 / kPanelAspect,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: preferences.wallpaper.gradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AuraRadius.control),
                  border: Border.all(color: accent.withValues(alpha: 0.5)),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AuraRadius.control),
                  child: Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: CustomPaint(
                          painter: WallpaperPatternPainter(
                            pattern: preferences.wallpaper.pattern,
                            color: accent,
                          ),
                        ),
                      ),
                      Positioned.fill(
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: 1 - preferences.previewDim,
                          ),
                        ),
                      ),
                      Positioned(
                        left: AuraSpace.sm,
                        right: AuraSpace.sm,
                        top: AuraSpace.sm,
                        child: Text(
                          _dateLabel,
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(color: accent),
                        ),
                      ),
                      Center(
                        child: _watchFaceFrame(
                          accent,
                          _previewClock(accent, text),
                        ),
                      ),
                      Positioned(
                        left: AuraSpace.sm,
                        right: AuraSpace.sm,
                        bottom: AuraSpace.sm,
                        child: Text(
                          '${preferences.wallpaper.label}  ·  '
                          '${preferences.brightness}%  ·  $_zoneLabel',
                          textAlign: TextAlign.center,
                          style: text.bodySmall?.copyWith(color: accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: AuraSpace.md),
          Text(
            'Live device time · $_zoneLabel. The second hand sweeps in real '
            'time. No pixel on a real panel is changed by this preview.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _watchFaceFrame(Color accent, Widget clock) {
    switch (preferences.watchFace) {
      case PanelWatchFace.classic:
        return clock;
      case PanelWatchFace.sport:
        return SizedBox(
          width: 168,
          height: 168,
          child: Center(
            child: FittedBox(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: accent.withValues(alpha: 0.55),
                    width: 3,
                  ),
                  color: Colors.black.withValues(alpha: 0.12),
                ),
                child: clock,
              ),
            ),
          ),
        );
      case PanelWatchFace.pulse:
        return SizedBox(
          width: 176,
          height: 176,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                painter: _PulseRingPainter(accent),
                child: const SizedBox.expand(),
              ),
              FittedBox(child: clock),
            ],
          ),
        );
      case PanelWatchFace.outline:
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accent.withValues(alpha: 0.45)),
            color: Colors.black.withValues(alpha: 0.14),
          ),
          child: FittedBox(child: clock),
        );
    }
  }

  Widget _analogFace(Color accent, TextTheme text, DateTime time) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        CustomPaint(
          size: const Size(104, 104),
          painter: _AnalogClockPainter(accent, time),
        ),
        const SizedBox(height: 4),
        Text(
          intl.DateFormat('HH:mm:ss').format(time),
          style: text.labelSmall?.copyWith(color: accent),
        ),
      ],
    );
  }

  Widget _previewClock(Color accent, TextTheme text) {
    final AnimationController? sweep = _sweep;
    switch (preferences.clockStyle) {
      case ClockStyle.analog:
        if (sweep == null) return _analogFace(accent, text, _now);
        return AnimatedBuilder(
          animation: sweep,
          builder: (BuildContext context, Widget? child) =>
              _analogFace(accent, text, clock.nowDeviceLocal()),
        );
      case ClockStyle.digital:
        return Text(
          _timeLabel,
          style: text.displaySmall?.copyWith(
            color: accent,
            fontWeight: FontWeight.w600,
          ),
        );
      case ClockStyle.minimal:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              _shortTimeLabel.replaceAll(':', ' '),
              style: text.headlineSmall?.copyWith(
                color: accent,
                letterSpacing: 8,
              ),
            ),
            Text(
              intl.DateFormat('EEE, d MMM').format(_now).toUpperCase(),
              style: text.labelSmall?.copyWith(
                color: accent,
                letterSpacing: 2,
              ),
            ),
            Text(
              'AURA',
              style: text.labelMedium?.copyWith(
                color: accent,
                letterSpacing: 4,
              ),
            ),
          ],
        );
      case ClockStyle.roman:
        return CustomPaint(
          size: const Size(112, 112),
          painter: _RomanClockPainter(accent, _now),
        );
      case ClockStyle.segment:
        return _SevenSegmentClock(
          accent: accent,
          text: text,
          time: _shortTimeLabel,
        );
      case ClockStyle.ring:
        return SizedBox(
          width: 132,
          height: 132,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              CustomPaint(
                painter: _RingClockPainter(accent, _now),
                child: const SizedBox.expand(),
              ),
              Text(
                _shortTimeLabel,
                style: text.titleMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        );
      case ClockStyle.flip:
        return _FlipClock(
          accent: accent,
          text: text,
          time: _shortTimeLabel,
        );
    }
  }
}

class _AnalogClockPainter extends CustomPainter {
  const _AnalogClockPainter(this.color, this.time);

  final Color color;
  final DateTime time;

  double get _seconds => time.second + time.microsecond / 1000000;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - 4;
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, paint);
    for (int hour = 0; hour < 12; hour++) {
      final double angle = (hour * 30 - 90) * math.pi / 180;
      final Offset direction = Offset(math.cos(angle), math.sin(angle));
      canvas.drawLine(
        center + direction * (radius - 9),
        center + direction * (radius - 2),
        paint,
      );
    }

    final double minuteProgress = time.minute + _seconds / 60;
    final double hourAngle =
        ((time.hour % 12) * 30 + minuteProgress * 0.5 - 90) * math.pi / 180;
    final double minuteAngle = (minuteProgress * 6 - 90) * math.pi / 180;
    final double secondAngle = (_seconds * 6 - 90) * math.pi / 180;

    canvas.drawLine(
      center,
      center + Offset(math.cos(hourAngle), math.sin(hourAngle)) * radius * 0.5,
      paint..strokeWidth = 3.5,
    );
    canvas.drawLine(
      center,
      center +
          Offset(math.cos(minuteAngle), math.sin(minuteAngle)) * radius * 0.74,
      paint..strokeWidth = 2.5,
    );
    canvas.drawLine(
      center - Offset(math.cos(secondAngle), math.sin(secondAngle)) * 8,
      center +
          Offset(math.cos(secondAngle), math.sin(secondAngle)) * radius * 0.86,
      paint
        ..color = color.withValues(alpha: 0.75)
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(center, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AnalogClockPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.time != time;
}

class _RomanClockPainter extends _AnalogClockPainter {
  const _RomanClockPainter(super.color, super.time);

  @override
  void paint(Canvas canvas, Size size) {
    super.paint(canvas, size);
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - 4;
    final TextPainter numeral = TextPainter(
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    );
    const List<(String, double)> marks = <(String, double)>[
      ('XII', -90),
      ('III', 0),
      ('VI', 90),
      ('IX', 180),
    ];
    for (final (String label, double degrees) in marks) {
      final double angle = degrees * math.pi / 180;
      final Offset position =
          center + Offset(math.cos(angle), math.sin(angle)) * (radius - 17);
      numeral.text = TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      );
      numeral.layout();
      numeral.paint(
        canvas,
        position - Offset(numeral.width / 2, numeral.height / 2),
      );
    }
  }
}

class _PulseRingPainter extends CustomPainter {
  const _PulseRingPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - 4;
    const List<double> scales = <double>[1, 0.78, 0.56];
    const List<double> alphas = <double>[0.18, 0.3, 0.5];
    for (int i = 0; i < scales.length; i++) {
      canvas.drawCircle(
        center,
        radius * scales[i],
        Paint()
          ..color = color.withValues(alpha: alphas[i])
          ..style = PaintingStyle.stroke
          ..strokeWidth = i == 0 ? 2 : 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _RingClockPainter extends CustomPainter {
  const _RingClockPainter(this.color, this.time);

  final Color color;
  final DateTime time;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = size.shortestSide / 2 - 6;
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final double seconds = time.second + time.microsecond / 1000000;
    final double minuteProgress = time.minute + seconds / 60;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = color.withValues(alpha: 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      (seconds / 60) * 2 * math.pi,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      -math.pi / 2,
      (minuteProgress / 60) * 2 * math.pi,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingClockPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.time != time;
}

class _SevenSegmentClock extends StatelessWidget {
  const _SevenSegmentClock({
    required this.accent,
    required this.text,
    required this.time,
  });

  final Color accent;
  final TextTheme text;
  final String time;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.35)),
      ),
      child: Text(
        time,
        style: text.headlineMedium?.copyWith(
          color: accent,
          fontFamily: 'monospace',
          fontWeight: FontWeight.w700,
          letterSpacing: 6,
        ),
      ),
    );
  }
}

class _FlipClock extends StatelessWidget {
  const _FlipClock({
    required this.accent,
    required this.text,
    required this.time,
  });

  final Color accent;
  final TextTheme text;
  final String time;

  Widget _tile(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: accent.withValues(alpha: 0.4)),
      ),
      child: Text(
        value,
        style: text.headlineSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _tile(time.substring(0, 2)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            ':',
            style: text.headlineSmall?.copyWith(color: accent),
          ),
        ),
        _tile(time.substring(3, 5)),
      ],
    );
  }
}

/// A setting row whose control never steals width from its label.
///
/// Below [kStackBreakpoint] the control is placed on its own line, aligned
/// under the text after the leading icon. Above it the original trailing
/// layout is preserved. Mirrors the responsive pattern in Settings.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.control,
  });

  static const double kStackBreakpoint = 620;
  static const double _textOffset = 30; // 18px icon + AuraSpace.sm gap.
  static const double _inlineControlWidth = 150;

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget Function(bool stacked) control;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xxs),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final Widget label = Row(
            children: <Widget>[
              Icon(icon, size: 18, color: AuraColors.textSecondary),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: text.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < kStackBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                label,
                Padding(
                  padding: const EdgeInsets.only(
                    left: _textOffset,
                    top: AuraSpace.xs,
                  ),
                  child: control(true),
                ),
              ],
            );
          }
          return Row(
            children: <Widget>[
              Expanded(child: label),
              const SizedBox(width: AuraSpace.sm),
              SizedBox(
                width: _inlineControlWidth,
                child: control(false),
              ),
            ],
          );
        },
      ),
    );
  }
}
