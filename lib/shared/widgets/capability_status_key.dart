import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/status_pill.dart';
import 'package:flutter/material.dart';

/// Explains the five availability labels used by Phase 3 workspaces.
///
/// Keeping the vocabulary in one place prevents a screen from implying that a
/// preview, a configuration or an unsupported path is a live capability.
class CapabilityStatusKey extends StatelessWidget {
  const CapabilityStatusKey({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Status key',
          style: Theme.of(context).textTheme.labelMedium,
        ),
        const SizedBox(height: AuraSpace.xs),
        Wrap(
          spacing: AuraSpace.xs,
          runSpacing: AuraSpace.xs,
          children: const <Widget>[
            StatusPill(
              label: 'Configured',
              color: AuraColors.primary,
              dense: true,
            ),
            StatusPill(
              label: 'Preview only',
              color: AuraColors.secondary,
              dense: true,
            ),
            StatusPill(
              label: 'Available on this computer',
              color: AuraColors.success,
              dense: true,
            ),
            StatusPill(
              label: 'Requires AURA hardware',
              color: AuraColors.warning,
              dense: true,
            ),
            StatusPill(
              label: 'Not implemented',
              color: AuraColors.textSecondary,
              dense: true,
            ),
          ],
        ),
      ],
    );
  }
}
