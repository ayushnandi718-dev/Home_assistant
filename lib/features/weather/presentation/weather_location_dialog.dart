import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/weather/domain/weather_location.dart';
import 'package:aura_hub/features/weather/presentation/weather_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Small manual-location dialog. AURA has no geolocation permission in this
/// build, so coordinates are always supplied by the user.
class WeatherLocationDialog extends ConsumerStatefulWidget {
  const WeatherLocationDialog({super.key, this.initialLocation});

  final WeatherLocation? initialLocation;

  @override
  ConsumerState<WeatherLocationDialog> createState() =>
      _WeatherLocationDialogState();
}

class _WeatherLocationDialogState extends ConsumerState<WeatherLocationDialog> {
  late final TextEditingController _label;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  String? _error;

  @override
  void initState() {
    super.initState();
    final WeatherLocation? initial = widget.initialLocation;
    _label = TextEditingController(text: initial?.label ?? '');
    _latitude = TextEditingController(
        text: initial == null ? '' : '${initial.latitude}');
    _longitude = TextEditingController(
        text: initial == null ? '' : '${initial.longitude}');
  }

  @override
  void dispose() {
    _label.dispose();
    _latitude.dispose();
    _longitude.dispose();
    super.dispose();
  }

  void _save() {
    try {
      final WeatherLocation location = WeatherLocation.parse(
        label: _label.text,
        latitude: _latitude.text,
        longitude: _longitude.text,
      );
      Navigator.of(context).pop(location);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _clear() async {
    await ref.read(weatherLocationProvider.notifier).clear();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Weather location', style: text.headlineSmall),
        const SizedBox(height: AuraSpace.xs),
        Text(
          'Enter a place name and its coordinates. Nothing is detected or '
          'stored without your input.',
          style: text.bodyMedium?.copyWith(color: AuraColors.textSecondary),
        ),
        const SizedBox(height: AuraSpace.lg),
        TextField(
          controller: _label,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Location name',
            hintText: 'e.g. Home',
            prefixIcon: Icon(Icons.place_outlined),
          ),
        ),
        const SizedBox(height: AuraSpace.sm),
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _latitude,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  hintText: '-90 to 90',
                ),
              ),
            ),
            const SizedBox(width: AuraSpace.sm),
            Expanded(
              child: TextField(
                controller: _longitude,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  hintText: '-180 to 180',
                ),
              ),
            ),
          ],
        ),
        if (_error != null) ...<Widget>[
          const SizedBox(height: AuraSpace.sm),
          Text(
            _error!,
            style: text.bodySmall?.copyWith(color: AuraColors.danger),
          ),
        ],
        const SizedBox(height: AuraSpace.lg),
        Row(
          children: <Widget>[
            if (widget.initialLocation != null)
              TextButton(onPressed: _clear, child: const Text('Clear')),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: AuraSpace.xs),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ],
    );
  }
}
