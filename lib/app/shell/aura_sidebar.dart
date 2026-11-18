import 'package:aura_hub/app/navigation.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/aura_logo.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AuraSidebar extends StatelessWidget {
  const AuraSidebar({
    super.key,
    required this.location,
    required this.expanded,
  });

  final String location;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;

    return GlassContainer(
      surface: AuraGlassSurface.chrome,
      radius: 0,
      showHighlight: false,
      border: const Border(
        right: BorderSide(color: AuraColors.border, width: 1),
      ),
      padding: EdgeInsets.symmetric(
        vertical: AuraSpace.lg,
        horizontal: expanded ? AuraSpace.md : AuraSpace.sm,
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment:
              expanded ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: expanded ? AuraSpace.sm : 0),
              child: Row(
                mainAxisAlignment: expanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: <Widget>[
                  const AuraLogo(size: 38),
                  if (expanded) ...<Widget>[
                    const SizedBox(width: AuraSpace.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            AppInfo.name.toUpperCase(),
                            style:
                                text.titleSmall?.copyWith(letterSpacing: 1.2),
                          ),
                          Text(
                            'Companion Console',
                            style: text.labelSmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AuraSpace.xl),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: expanded
                      ? CrossAxisAlignment.start
                      : CrossAxisAlignment.center,
                  children: <Widget>[
                    for (final AuraNavSection section
                        in AuraNavSection.values) ...<Widget>[
                      if (expanded)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AuraSpace.sm + 2,
                            0,
                            0,
                            AuraSpace.sm,
                          ),
                          child: Text(
                            sectionLabel(section),
                            style: text.labelSmall,
                          ),
                        )
                      else
                        const SizedBox(height: AuraSpace.sm),
                      for (final AuraDestination destination
                          in auraDestinations.where(
                        (AuraDestination item) => item.section == section,
                      ))
                        _NavTile(
                          destination: destination,
                          selected: location == destination.path,
                          expanded: expanded,
                        ),
                      const SizedBox(height: AuraSpace.md),
                    ],
                  ],
                ),
              ),
            ),
            if (expanded)
              GlassContainer(
                surface: AuraGlassSurface.panel,
                width: double.infinity,
                radius: AuraRadius.control,
                padding: const EdgeInsets.all(AuraSpace.sm),
                blur: 8,
                fill: 0.5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      AppInfo.phase.toUpperCase(),
                      style:
                          text.labelSmall?.copyWith(color: AuraColors.primary),
                    ),
                    const SizedBox(height: AuraSpace.xxs),
                    Text(
                      'v${AppInfo.version}  -  Demo mode',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              )
            else
              Tooltip(
                message: 'v${AppInfo.version} - ${AppInfo.phase}',
                child: Icon(Icons.info_outline_rounded,
                    size: 18, color: AuraColors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.destination,
    required this.selected,
    required this.expanded,
  });

  final AuraDestination destination;
  final bool selected;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final Color iconColor =
        selected ? AuraColors.primary : AuraColors.textSecondary;
    final IconData icon =
        selected ? destination.selectedIcon : destination.icon;

    final Widget tile = GlassContainer(
      surface: selected ? AuraGlassSurface.strong : AuraGlassSurface.panel,
      radius: AuraRadius.control,
      blur: selected ? 12 : 0,
      fill: selected ? 0.58 : 0,
      shadows: selected ? null : const <BoxShadow>[],
      showHighlight: selected,
      margin: const EdgeInsets.only(bottom: AuraSpace.xxs),
      borderColor: selected
          ? AuraColors.primary.withValues(alpha: 0.34)
          : Colors.transparent,
      padding: EdgeInsets.symmetric(
        horizontal: expanded ? AuraSpace.sm : AuraSpace.xs,
      ),
      onTap: () => context.go(destination.path),
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisAlignment:
              expanded ? MainAxisAlignment.start : MainAxisAlignment.center,
          children: <Widget>[
            if (expanded) ...<Widget>[
              SizedBox(width: 46, child: _navIcon(context, icon, iconColor)),
              Expanded(
                child: AnimatedDefaultTextStyle(
                  duration: AuraMotion.of(context, AuraMotion.fast),
                  curve: AuraMotion.standard,
                  style:
                      (selected ? text.titleSmall : text.bodyLarge)?.copyWith(
                            color: selected
                                ? AuraColors.textPrimary
                                : AuraColors.textSecondary,
                            fontSize: 13,
                          ) ??
                          TextStyle(
                            fontSize: 13,
                            color: selected
                                ? AuraColors.textPrimary
                                : AuraColors.textSecondary,
                          ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  child: Text(destination.label),
                ),
              ),
            ] else
              _navIcon(context, icon, iconColor),
          ],
        ),
      ),
    );

    if (expanded) return tile;
    return Tooltip(message: destination.label, child: tile);
  }

  Widget _navIcon(BuildContext context, IconData icon, Color color) {
    return AnimatedSwitcher(
      duration: AuraMotion.of(context, AuraMotion.fast),
      switchInCurve: AuraMotion.enter,
      switchOutCurve: AuraMotion.exit,
      transitionBuilder: (Widget child, Animation<double> animation) {
        return ScaleTransition(
          scale: Tween<double>(begin: 0.78, end: 1).animate(animation),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: Icon(
        icon,
        key: ValueKey<IconData>(icon),
        size: 19,
        color: color,
      ),
    );
  }
}
