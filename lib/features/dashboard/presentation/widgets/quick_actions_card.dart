import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:aura_hub/shared/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class QuickActionsCard extends StatelessWidget {
  const QuickActionsCard({super.key});

  static const List<_Action> _actions = <_Action>[
    _Action(
      icon: Icons.add_circle_outline_rounded,
      label: 'Add device',
      caption: 'Register AURA hardware',
      route: AppRoutes.devices,
    ),
    _Action(
      icon: Icons.tune_rounded,
      label: 'Open device settings',
      caption: 'Configure the active device',
      route: AppRoutes.devices,
    ),
    _Action(
      icon: Icons.group_outlined,
      label: 'Manage profiles',
      caption: 'Ayush and Family workspaces',
      route: AppRoutes.profiles,
    ),
    _Action(
      icon: Icons.monitor_heart_outlined,
      label: 'Run diagnostics',
      caption: 'Inspect health and logs',
      route: AppRoutes.diagnostics,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(AuraSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AuraSpace.sm,
              vertical: AuraSpace.xs,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('QUICK ACTIONS', style: text.labelMedium),
                const SizedBox(height: AuraSpace.xxs),
                Text('Go somewhere', style: text.titleLarge),
              ],
            ),
          ),
          const SizedBox(height: AuraSpace.sm),
          for (final _Action action in _actions)
            _ActionTile(action: action, text: text),
        ],
      ),
    );
  }
}

class _Action {
  const _Action({
    required this.icon,
    required this.label,
    required this.caption,
    required this.route,
  });

  final IconData icon;
  final String label;
  final String caption;
  final String route;
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.action, required this.text});

  final _Action action;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => context.go(action.route),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AuraSpace.sm,
            vertical: AuraSpace.sm + 2,
          ),
          child: Row(
            children: <Widget>[
              GlassContainer(
                width: 34,
                height: 34,
                padding: EdgeInsets.zero,
                radius: 10,
                blur: 8,
                fill: 0.5,
                showHighlight: false,
                borderColor: AuraColors.primary.withValues(alpha: 0.28),
                child: Icon(action.icon, size: 17, color: AuraColors.primary),
              ),
              const SizedBox(width: AuraSpace.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(action.label, style: text.titleSmall),
                    const SizedBox(height: 2),
                    Text(action.caption, style: text.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  size: 18, color: AuraColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
