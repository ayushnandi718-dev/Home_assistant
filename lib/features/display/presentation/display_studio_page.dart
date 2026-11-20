import 'dart:math' as math;

import 'package:aura_hub/core/settings/app_settings.dart';
import 'package:aura_hub/core/settings/app_settings_providers.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/dashboard/domain/dashboard_layout.dart';
import 'package:aura_hub/features/dashboard/presentation/dashboard_layout_provider.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/dashboard_widget_studio_dialog.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
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
                  final Widget preview =
                      _PanelPreview(preferences: preferences);
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
              Text('Brightness, timeout & sleep', style: text.titleLarge),
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
            trailing: SizedBox(
              width: 150,
              child: DropdownButton<ScreenTimeout>(
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
            trailing: SizedBox(
              width: 150,
              child: DropdownButton<int>(
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
          ),
          _SettingRow(
            icon: Icons.wb_sunny_outlined,
            title: 'Sleep ends',
            subtitle: 'Local time on the panel.',
            trailing: SizedBox(
              width: 150,
              child: DropdownButton<int>(
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
              Text('Theme, wallpaper & clock', style: text.titleLarge),
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
            trailing: SizedBox(
              width: 150,
              child: DropdownButton<AuraThemeMode>(
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
          Wrap(
            spacing: AuraSpace.xs,
            children: <Widget>[
              for (final PanelWallpaper wallpaper in PanelWallpaper.values)
                ChoiceChip(
                  label: Text(wallpaper.label),
                  selected: preferences.wallpaper == wallpaper,
                  showCheckmark: false,
                  onSelected: (_) => controller.update(
                    preferences.copyWith(wallpaper: wallpaper),
                  ),
                ),
            ],
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
              Text('Dashboard widgets', style: text.titleLarge),
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
              Text('Orientation & saved state', style: text.titleLarge),
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
          SegmentedButton<PanelOrientation>(
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
          const SizedBox(height: AuraSpace.md),
          Row(
            children: <Widget>[
              const StatusPill(
                label: 'Requires AURA hardware to apply',
                color: AuraColors.warning,
                dense: true,
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: ValueListenableBuilder<DisplaySaveState>(
                  valueListenable: controller.saveState,
                  builder: (BuildContext context, DisplaySaveState state, _) {
                    return Text(
                      state.label,
                      textAlign: TextAlign.end,
                      style: text.bodySmall?.copyWith(
                        color: state == DisplaySaveState.failed
                            ? AuraColors.danger
                            : AuraColors.textSecondary,
                      ),
                    );
                  },
                ),
              ),
            ],
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

class _PanelPreview extends StatelessWidget {
  const _PanelPreview({required this.preferences});

  final DisplayPreferences preferences;

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
              aspectRatio: landscape ? 1.6 : 0.72,
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
                        child: ColoredBox(
                          color: Colors.black.withValues(
                            alpha: 1 - preferences.previewDim,
                          ),
                        ),
                      ),
                      Center(child: _previewClock(accent, text)),
                      Positioned(
                        left: AuraSpace.sm,
                        right: AuraSpace.sm,
                        bottom: AuraSpace.sm,
                        child: Text(
                          '${preferences.wallpaper.label}  ·  '
                          '${preferences.brightness}%  ·  '
                          '${preferences.orientation.label}',
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
            'Displayed at a fixed 10:09 so style changes are easy to compare. '
            'No pixel on a real panel is changed by this preview.',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _previewClock(Color accent, TextTheme text) {
    switch (preferences.clockStyle) {
      case ClockStyle.analog:
        return CustomPaint(
          size: const Size(104, 104),
          painter: _AnalogClockPainter(accent),
        );
      case ClockStyle.digital:
        return Text(
          '10:09',
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
              '10 09',
              style: text.headlineSmall?.copyWith(
                color: accent,
                letterSpacing: 8,
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
    }
  }
}

class _AnalogClockPainter extends CustomPainter {
  const _AnalogClockPainter(this.color);

  final Color color;

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
    final double hourAngle = (10 * 30 + 9 * 0.5 - 90) * math.pi / 180;
    final double minuteAngle = (9 * 6 - 90) * math.pi / 180;
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
    canvas.drawCircle(center, 3.5, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _AnalogClockPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xxs),
      child: Row(
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
          const SizedBox(width: AuraSpace.sm),
          trailing,
        ],
      ),
    );
  }
}
