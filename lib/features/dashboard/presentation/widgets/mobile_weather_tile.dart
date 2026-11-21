import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/aura_tile.dart';
import 'package:aura_hub/features/weather/domain/weather_location.dart';
import 'package:aura_hub/features/weather/domain/weather_snapshot.dart';
import 'package:aura_hub/features/weather/presentation/weather_location_dialog.dart';
import 'package:aura_hub/features/weather/presentation/weather_providers.dart';
import 'package:aura_hub/shared/widgets/glass/glass_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Real current conditions with honest unset, loading, cached and error states.
class MobileWeatherTile extends ConsumerWidget {
  const MobileWeatherTile({super.key});

  static const Key tileKey = ValueKey<String>('weather-tile');

  Future<void> _openLocationDialog(
    BuildContext context,
    WidgetRef ref,
    WeatherLocation? current,
  ) async {
    final WeatherLocation? next = await showGlassDialog<WeatherLocation>(
      context: context,
      keyboardAware: true,
      width: 420,
      padding: const EdgeInsets.all(24),
      child: WeatherLocationDialog(initialLocation: current),
    );
    if (next == null || !context.mounted) return;
    await ref.read(weatherLocationProvider.notifier).save(next);
    if (!context.mounted) return;
    await ref.read(weatherProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final WeatherLocation? location = ref.watch(weatherLocationProvider);
    final WeatherState weather = ref.watch(weatherProvider);
    final WeatherSnapshot? snapshot = weather.snapshot;

    final IconData icon;
    final Color accent;
    final String value;
    final String? sub;
    final AuraTileState state;

    if (snapshot != null) {
      final WeatherCondition condition = snapshot.condition;
      icon = _iconFor(condition);
      accent = _accentFor(condition);
      value = snapshot.temperatureLabel;
      final String suffix = weather.status == WeatherStatus.loading
          ? ' · updating'
          : weather.status == WeatherStatus.error
              ? ' · cached'
              : '';
      sub = '${snapshot.locationLabel} · ${condition.label}$suffix';
      state = AuraTileState.normal;
    } else {
      switch (weather.status) {
        case WeatherStatus.loading:
          icon = Icons.cloud_outlined;
          accent = AuraColors.primary;
          value = 'Loading…';
          sub = 'Fetching current conditions';
          state = AuraTileState.loading;
        case WeatherStatus.error:
          icon = Icons.cloud_off_outlined;
          accent = AuraColors.warning;
          value = 'Unavailable';
          sub = weather.message ?? 'Weather could not be loaded';
          state = AuraTileState.unavailable;
        case WeatherStatus.unset:
        case WeatherStatus.success:
          icon = Icons.location_on_outlined;
          accent = AuraColors.primary;
          value = 'Set location';
          sub = 'Tap to enter coordinates';
          state = AuraTileState.normal;
      }
    }

    return SizedBox(
      key: tileKey,
      width: double.infinity,
      child: AuraTile(
        icon: icon,
        accent: accent,
        label: 'Weather',
        value: value,
        sub: sub,
        height: 152,
        state: state,
        tooltip: 'Change weather location',
        onTap: () => _openLocationDialog(context, ref, location),
      ),
    );
  }

  IconData _iconFor(WeatherCondition condition) => switch (condition) {
        WeatherCondition.clear => Icons.wb_sunny_rounded,
        WeatherCondition.partlyCloudy => Icons.cloud_outlined,
        WeatherCondition.fog => Icons.blur_on_rounded,
        WeatherCondition.rain => Icons.umbrella_rounded,
        WeatherCondition.snow => Icons.ac_unit_rounded,
        WeatherCondition.thunderstorm => Icons.bolt_rounded,
        WeatherCondition.unknown => Icons.cloud_outlined,
      };

  Color _accentFor(WeatherCondition condition) => switch (condition) {
        WeatherCondition.clear => const Color(0xFFF5C97B),
        WeatherCondition.partlyCloudy => const Color(0xFF8AB4FF),
        WeatherCondition.fog => const Color(0xFFA9C6D6),
        WeatherCondition.rain => const Color(0xFF62D9F2),
        WeatherCondition.snow => const Color(0xFFBFE8FF),
        WeatherCondition.thunderstorm => const Color(0xFFB69CFF),
        WeatherCondition.unknown => AuraColors.primary,
      };
}
