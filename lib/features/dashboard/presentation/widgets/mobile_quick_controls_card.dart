import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:aura_hub/features/display/presentation/display_providers.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// Everyday panel controls.
///
/// Every editable value here changes the profile-scoped local configuration and
/// the local preview only. Hardware commands are shown as unavailable until a
/// real ESP32 transport can report capability and acknowledge execution.
class MobileQuickControlsCard extends ConsumerStatefulWidget {
  const MobileQuickControlsCard({super.key});

  @override
  ConsumerState<MobileQuickControlsCard> createState() =>
      _MobileQuickControlsCardState();
}

class _MobileQuickControlsCardState
    extends ConsumerState<MobileQuickControlsCard> {
  @override
  Widget build(BuildContext context) {
    final DisplayPreferences preferences =
        ref.watch(displayPreferencesProvider);
    final DisplayPreferencesController controller =
        ref.read(activeDisplayPreferencesControllerProvider);
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              GlassContainer(
                width: 38,
                height: 38,
                padding: EdgeInsets.zero,
                radius: 11,
                blur: 0,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.primary.withValues(alpha: 0.28),
                child: const Icon(Icons.tune_rounded,
                    size: 19, color: AuraColors.primary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(child: Text('Quick controls', style: text.titleLarge)),
              const StatusPill(
                label: 'Local preview',
                color: AuraColors.secondary,
                dense: true,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          _BrightnessControl(
            value: preferences.brightness,
            onChanged: (int value) =>
                controller.update(preferences.copyWith(brightness: value)),
          ),
          const _SectionDivider(),
          const _ScreenPowerControl(),
          const _SectionDivider(),
          _WallpaperControl(
            selected: preferences.wallpaper,
            onSelected: (PanelWallpaper wallpaper) =>
                controller.update(preferences.copyWith(wallpaper: wallpaper)),
          ),
          const _SectionDivider(),
          _ClockControl(
            style: preferences.clockStyle,
            onStyleChanged: (ClockStyle style) =>
                controller.update(preferences.copyWith(clockStyle: style)),
          ),
          const _SectionDivider(),
          _NightModeControl(
            schedule: preferences.sleepSchedule,
            onScheduleChanged: (SleepSchedule schedule) => controller
                .update(preferences.copyWith(sleepSchedule: schedule)),
          ),
          const SizedBox(height: AuraSpace.md),
          Wrap(
            spacing: AuraSpace.sm,
            runSpacing: AuraSpace.xs,
            children: <Widget>[
              TextButton.icon(
                onPressed: () => context.go(AppRoutes.displayStudio),
                icon: const Icon(Icons.open_in_new_rounded, size: 16),
                label: const Text('Display Studio'),
              ),
              TextButton.icon(
                onPressed: () => context.go(AppRoutes.diagnostics),
                icon: const Icon(Icons.monitor_heart_outlined, size: 16),
                label: const Text('Diagnostics'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: AuraSpace.sm),
        child: Divider(height: 1),
      );
}

class _ControlLabel extends StatelessWidget {
  const _ControlLabel({required this.label, this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Row(
      children: <Widget>[
        Expanded(child: Text(label, style: text.titleSmall)),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class _LocalHint extends StatelessWidget {
  const _LocalHint(this.message);

  final String message;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: AuraSpace.xxs),
        child: Text(
          message,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AuraColors.textSecondary,
              ),
        ),
      );
}

class _BrightnessControl extends StatelessWidget {
  const _BrightnessControl({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ControlLabel(
          label: 'Brightness',
          trailing: Text(
            '$value%',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        Slider(
          value: value.toDouble(),
          min: DisplayPreferences.minBrightness.toDouble(),
          max: DisplayPreferences.maxBrightness.toDouble(),
          divisions: DisplayPreferences.maxBrightness -
              DisplayPreferences.minBrightness,
          label: '$value%',
          onChanged: (double next) => onChanged(next.round()),
        ),
        const _LocalHint(
          'Saved locally for the preview. Panel brightness needs a real '
          'device command and acknowledgement.',
        ),
      ],
    );
  }
}

class _ScreenPowerControl extends StatelessWidget {
  const _ScreenPowerControl();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text('Screen power',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              const StatusPill(
                label: 'Unavailable',
                color: AuraColors.textSecondary,
                dense: true,
              ),
              IgnorePointer(
                child: Switch(value: false, onChanged: (_) {}),
              ),
            ],
          ),
        ),
        const _LocalHint(
          'The confirmed screen state and ON/OFF command require a connected '
          'panel. This toggle stays disabled rather than guessing.',
        ),
      ],
    );
  }
}

class _WallpaperControl extends StatelessWidget {
  const _WallpaperControl({
    required this.selected,
    required this.onSelected,
  });

  final PanelWallpaper selected;
  final ValueChanged<PanelWallpaper> onSelected;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        _ControlLabel(
          label: 'Wallpaper',
          trailing: Text(
            selected.label,
            style: text.labelMedium,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: AuraSpace.sm),
        SizedBox(
          height: 62,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: PanelWallpaper.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: AuraSpace.sm),
            itemBuilder: (BuildContext context, int index) {
              final PanelWallpaper wallpaper = PanelWallpaper.values[index];
              final bool isSelected = wallpaper == selected;
              return SizedBox(
                width: 76,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AuraRadius.control),
                    onTap: () => onSelected(wallpaper),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(AuraRadius.control),
                        gradient: LinearGradient(colors: wallpaper.gradient),
                        border: Border.all(
                          color: isSelected
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.18),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      padding: const EdgeInsets.all(AuraSpace.xxs),
                      alignment: Alignment.bottomCenter,
                      child: Text(
                        wallpaper.label,
                        style: text.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight:
                              isSelected ? FontWeight.w700 : FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const _LocalHint(
          'Changes the local preview only. Uploading or applying a wallpaper '
          'requires ESP32 transfer support.',
        ),
      ],
    );
  }
}

class _ClockControl extends StatelessWidget {
  const _ClockControl({
    required this.style,
    required this.onStyleChanged,
  });

  final ClockStyle style;
  final ValueChanged<ClockStyle> onStyleChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const _ControlLabel(label: 'Clock style'),
        const SizedBox(height: AuraSpace.xs),
        Wrap(
          spacing: AuraSpace.sm,
          runSpacing: AuraSpace.xs,
          children: <Widget>[
            ChoiceChip(
              label: const Text('Digital'),
              selected: style == ClockStyle.digital,
              onSelected: (_) => onStyleChanged(ClockStyle.digital),
            ),
            ChoiceChip(
              label: const Text('Analog'),
              selected: style == ClockStyle.analog,
              onSelected: (_) => onStyleChanged(ClockStyle.analog),
            ),
          ],
        ),
        const SizedBox(height: AuraSpace.sm),
        const _ControlLabel(label: 'Clock format'),
        const SizedBox(height: AuraSpace.xs),
        Wrap(
          spacing: AuraSpace.sm,
          runSpacing: AuraSpace.xs,
          children: const <Widget>[
            Tooltip(
              message: 'Requires a reported panel capability',
              child: ChoiceChip(label: Text('24-hour'), selected: true),
            ),
            Tooltip(
              message: 'Requires a reported panel capability',
              child: ChoiceChip(
                label: Text('12-hour'),
                selected: false,
                onSelected: null,
              ),
            ),
          ],
        ),
        const _LocalHint(
          'Clock style is saved locally. 12/24-hour selection stays disabled '
          'until a connected panel reports that capability.',
        ),
      ],
    );
  }
}

class _NightModeControl extends StatelessWidget {
  const _NightModeControl({
    required this.schedule,
    required this.onScheduleChanged,
  });

  final SleepSchedule schedule;
  final ValueChanged<SleepSchedule> onScheduleChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 48,
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text('Night mode schedule',
                    style: Theme.of(context).textTheme.titleSmall),
              ),
              Switch(
                value: schedule.enabled,
                onChanged: (bool enabled) =>
                    onScheduleChanged(schedule.copyWith(enabled: enabled)),
              ),
            ],
          ),
        ),
        Row(
          children: <Widget>[
            Expanded(
              child: _TimeDropdown(
                label: 'Start',
                value: schedule.startMinutes,
                onChanged: (int minutes) => onScheduleChanged(
                  schedule.copyWith(startMinutes: minutes),
                ),
              ),
            ),
            const SizedBox(width: AuraSpace.sm),
            Expanded(
              child: _TimeDropdown(
                label: 'End',
                value: schedule.endMinutes,
                onChanged: (int minutes) => onScheduleChanged(
                  schedule.copyWith(endMinutes: minutes),
                ),
              ),
            ),
          ],
        ),
        _LocalHint(
          schedule.enabled
              ? 'Scheduled for ${schedule.startLabel}–${schedule.endLabel}. '
                  'Saved locally; the panel must stay connected to apply a '
                  'schedule on-device.'
              : 'Schedule is off. Saved locally; applying it to a physical '
                  'panel is not implemented yet.',
        ),
      ],
    );
  }
}

class _TimeDropdown extends StatelessWidget {
  const _TimeDropdown({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: AuraSpace.sm, vertical: 8),
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: value,
          isDense: true,
          isExpanded: true,
          items: <int>[
            for (int minutes = 0; minutes <= 1410; minutes += 30) minutes,
          ].map((int minutes) {
            return DropdownMenuItem<int>(
              value: minutes,
              child: Text(SleepSchedule.formatMinutes(minutes)),
            );
          }).toList(),
          onChanged: (int? next) {
            if (next != null) onChanged(next);
          },
        ),
      ),
    );
  }
}
