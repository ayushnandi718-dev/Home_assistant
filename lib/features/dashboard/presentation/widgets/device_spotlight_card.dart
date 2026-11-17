import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/core/utilities/formatters.dart';
import 'package:aura_hub/features/dashboard/presentation/widgets/device_frame.dart';
import 'package:aura_hub/features/devices/domain/aura_device.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class DeviceSpotlightCard extends StatelessWidget {
  const DeviceSpotlightCard({super.key, required this.devices});

  /// Registered AURA devices. The Windows host must never appear here.
  final List<AuraDevice> devices;

  @override
  Widget build(BuildContext context) {
    final AuraDevice? device = devices.isEmpty ? null : devices.first;
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text('AURA DEVICES', style: text.labelMedium),
                    const SizedBox(height: AuraSpace.xxs),
                    Text(
                      device == null
                          ? 'No hardware connected'
                          : 'Your AURA companion',
                      style: text.titleLarge,
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: device == null
                    ? 'NOT LINKED'
                    : device.connectionState.label.toUpperCase(),
                color: device != null && device.isOnline
                    ? AuraColors.success
                    : AuraColors.warning,
              ),
            ],
          ),
          const SizedBox(height: AuraSpace.lg),
          if (device == null)
            const _EmptyDeviceState()
          else
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints constraints) {
                const Widget frame = DeviceFrame();
                final Widget details = _DeviceDetails(device: device);
                if (constraints.maxWidth >= 580) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      frame,
                      const SizedBox(width: AuraSpace.lg),
                      Expanded(child: details),
                    ],
                  );
                }
                return Column(
                  children: <Widget>[
                    frame,
                    const SizedBox(height: AuraSpace.lg),
                    details,
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _DeviceDetails extends StatelessWidget {
  const _DeviceDetails({required this.device});

  final AuraDevice device;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final String battery = device.batteryPercent == null
        ? 'Not reported'
        : '${device.batteryPercent}%';
    final String lastSeen = device.lastSeen == null
        ? 'Unavailable'
        : formatRelativeTime(device.lastSeen!);
    final String lastSync = device.lastSynced == null
        ? 'Never'
        : formatRelativeTime(device.lastSynced!);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(device.name, style: text.headlineSmall),
        const SizedBox(height: AuraSpace.xxs),
        Text(device.model, style: text.bodyMedium),
        const SizedBox(height: AuraSpace.md),
        _DetailRow(
          icon: Icons.memory_outlined,
          label: 'Firmware',
          value: device.firmwareVersion,
        ),
        _DetailRow(
          icon: Icons.power_settings_new_outlined,
          label: 'Battery',
          value: battery,
        ),
        _DetailRow(
          icon: Icons.history_rounded,
          label: 'Last seen',
          value: lastSeen,
        ),
        _DetailRow(
          icon: Icons.sync_outlined,
          label: 'Last sync',
          value: lastSync,
        ),
        const SizedBox(height: AuraSpace.lg),
        OutlinedButton.icon(
          onPressed: () => context.go(AppRoutes.devices),
          icon: const Icon(Icons.tune_rounded, size: 16),
          label: const Text('Device details'),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: AuraSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Icon(icon, size: 16, color: AuraColors.textSecondary),
          const SizedBox(width: AuraSpace.sm),
          SizedBox(width: 84, child: Text(label, style: text.bodySmall)),
          Expanded(
            child: Text(
              value,
              style: text.bodyMedium?.copyWith(color: AuraColors.textPrimary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyDeviceState extends StatelessWidget {
  const _EmptyDeviceState();

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AuraSpace.xl),
      decoration: BoxDecoration(
        color: AuraColors.elevated.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(AuraRadius.card),
        border: Border.all(color: AuraColors.border),
      ),
      child: Column(
        children: <Widget>[
          const DeviceFrame(),
          const SizedBox(height: AuraSpace.lg),
          Icon(Icons.devices_other_outlined,
              size: 30, color: AuraColors.textSecondary),
          const SizedBox(height: AuraSpace.sm),
          Text('No AURA devices connected', style: text.titleMedium),
          const SizedBox(height: AuraSpace.xxs),
          Text(
            'Windows host readings are shown separately above. They are PC '
            'telemetry, not AURA hardware data.',
            style: text.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
