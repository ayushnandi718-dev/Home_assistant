import 'package:aura_hub/app/navigation.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_bottom_navigation.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

const List<String> _primaryPaths = <String>[
  AppRoutes.dashboard,
  AppRoutes.devices,
  AppRoutes.displayStudio,
  AppRoutes.diagnostics,
];

class MobileBottomBar extends StatelessWidget {
  const MobileBottomBar({super.key, required this.location});

  final String location;

  @override
  Widget build(BuildContext context) {
    final int primaryIndex = _primaryPaths.indexOf(location);
    final int selectedIndex = primaryIndex == -1 ? 4 : primaryIndex;

    return GlassBottomNavigation(
      selectedIndex: selectedIndex,
      onDestinationSelected: (int index) {
        if (index == 4) {
          _showMoreSheet(context);
          return;
        }
        context.go(_primaryPaths[index]);
      },
      destinations: const <NavigationDestination>[
        NavigationDestination(
          icon: Icon(Icons.space_dashboard_outlined),
          selectedIcon: Icon(Icons.space_dashboard_rounded),
          label: 'Home',
        ),
        NavigationDestination(
          icon: Icon(Icons.devices_other_outlined),
          selectedIcon: Icon(Icons.devices_other_rounded),
          label: 'Devices',
        ),
        NavigationDestination(
          icon: Icon(Icons.palette_outlined),
          selectedIcon: Icon(Icons.palette_rounded),
          label: 'Display',
        ),
        NavigationDestination(
          icon: Icon(Icons.monitor_heart_outlined),
          selectedIcon: Icon(Icons.monitor_heart_rounded),
          label: 'Diagnostics',
        ),
        NavigationDestination(
          icon: Icon(Icons.more_horiz_rounded),
          selectedIcon: Icon(Icons.more_horiz_rounded),
          label: 'More',
        ),
      ],
    );
  }

  void _showMoreSheet(BuildContext context) {
    final List<AuraDestination> others = auraDestinations
        .where((AuraDestination item) => !_primaryPaths.contains(item.path))
        .toList();

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return GlassContainer(
          surface: AuraGlassSurface.chrome,
          radius: 0,
          blur: 18,
          fill: 0.55,
          padding: EdgeInsets.zero,
          border: const Border(
            top: BorderSide(color: AuraColors.border),
            left: BorderSide(color: AuraColors.border),
            right: BorderSide(color: AuraColors.border),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AuraSpace.lg,
                AuraSpace.md,
                AuraSpace.lg,
                AuraSpace.lg,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AuraColors.border,
                      borderRadius: BorderRadius.circular(AuraRadius.pill),
                    ),
                  ),
                  const SizedBox(height: AuraSpace.md),
                  Text(
                    'MORE',
                    style: Theme.of(sheetContext).textTheme.labelMedium,
                  ),
                  const SizedBox(height: AuraSpace.sm),
                  for (final AuraDestination destination in others)
                    _SheetTile(
                      destination: destination,
                      selected: location == destination.path,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        context.go(destination.path);
                      },
                    ),
                  const SizedBox(height: AuraSpace.sm),
                  Text(
                    '${AppInfo.name} v${AppInfo.version} - ${AppInfo.phase}',
                    style: Theme.of(sheetContext).textTheme.labelSmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SheetTile extends StatelessWidget {
  const _SheetTile({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AuraDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        selected ? destination.selectedIcon : destination.icon,
        color: selected ? AuraColors.primary : AuraColors.textSecondary,
        size: 20,
      ),
      title: Text(
        destination.label,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color:
                  selected ? AuraColors.textPrimary : AuraColors.textSecondary,
            ),
      ),
      trailing: const Icon(Icons.chevron_right_rounded,
          size: 18, color: AuraColors.textSecondary),
      onTap: onTap,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AuraRadius.control),
      ),
    );
  }
}
