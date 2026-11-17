import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';

/// Manual startup instructions only. The Flutter app must never launch
/// PowerShell, create background processes, or start the API by itself.
class ApiStartupGuide extends StatelessWidget {
  const ApiStartupGuide({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.terminal_rounded, color: AuraColors.primary),
              const SizedBox(width: AuraSpace.sm),
              Text('Start the local telemetry API', style: text.titleMedium),
            ],
          ),
          const SizedBox(height: AuraSpace.md),
          const _CommandStep(
            number: '1',
            title: 'Open PowerShell in the AURA Hub project folder',
            command: 'cd "<AURA Hub project folder>"',
          ),
          const _CommandStep(
            number: '2',
            title: 'Run the provided startup script',
            command:
                'powershell -ExecutionPolicy Bypass -File scripts\\start_aura_api.ps1',
          ),
          if (!compact) ...<Widget>[
            const SizedBox(height: AuraSpace.sm),
            Text(
              'The script prepares server\\.venv and serves loopback telemetry '
              'on http://127.0.0.1:8765. AURA Hub only reads that endpoint; '
              'it never starts or stops the process for you.',
              style: text.bodySmall,
            ),
          ],
        ],
      ),
    );
  }
}

class _CommandStep extends StatelessWidget {
  const _CommandStep({
    required this.number,
    required this.title,
    required this.command,
  });

  final String number;
  final String title;
  final String command;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AuraSpace.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          CircleAvatar(
            radius: 13,
            backgroundColor: AuraColors.primary.withValues(alpha: 0.12),
            child: Text(number, style: text.labelSmall),
          ),
          const SizedBox(width: AuraSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: text.bodyMedium),
                const SizedBox(height: AuraSpace.xxs),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AuraSpace.sm),
                  decoration: BoxDecoration(
                    color: AuraColors.backgroundDeep,
                    borderRadius: BorderRadius.circular(AuraRadius.control),
                    border: Border.all(color: AuraColors.border),
                  ),
                  child: SelectableText(
                    command,
                    style: text.bodySmall?.copyWith(
                      color: AuraColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
