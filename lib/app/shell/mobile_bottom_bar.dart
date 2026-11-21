import 'dart:async';

import 'package:aura_hub/app/navigation.dart';
import 'package:aura_hub/core/constants/app_info.dart';
import 'package:aura_hub/core/constants/app_routes.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';
import 'package:forui/forui.dart';
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

    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AuraSpace.md,
          0,
          AuraSpace.md,
          AuraSpace.sm,
        ),
        // The capsule is opaque by design; AppShell paints a soft fade behind
        // it. Keeping the bar as the only child preserves its existing inset,
        // size, radius and touch targets while removing stale glass sampling.
        child: FBottomNavigationBar(
          index: selectedIndex,
          onChange: (int index) {
            if (index == 4) {
              _showMoreSheet(context);
              return;
            }
            context.go(_primaryPaths[index]);
          },
          children: <FBottomNavigationBarItem>[
            FBottomNavigationBarItem(
              icon: const _NavIcon(FLucideIcons.house),
              label: const Text('Home'),
            ),
            FBottomNavigationBarItem(
              icon: const _NavIcon(FLucideIcons.cpu),
              label: const Text('Devices'),
            ),
            FBottomNavigationBarItem(
              icon: const _NavIcon(FLucideIcons.palette),
              label: const Text('Display'),
            ),
            FBottomNavigationBarItem(
              icon: const _NavIcon(FLucideIcons.heartPulse),
              label: const Text('Diagnostics'),
            ),
            FBottomNavigationBarItem(
              icon: const _NavIcon(FLucideIcons.ellipsis),
              label: const Text('More'),
            ),
          ],
        ),
      ),
    );
  }

  void _showMoreSheet(BuildContext context) {
    unawaited(_openMoreSheet(context));
  }

  Future<void> _openMoreSheet(BuildContext context) async {
    final List<AuraDestination> others = auraDestinations
        .where((AuraDestination item) => !_primaryPaths.contains(item.path))
        .toList();
    final AuraPalette palette = AuraPaletteTheme.of(context);

    // Adapt to the live viewport: keyboard, gesture/3-button navigation and
    // status-bar cutouts all reduce the space available to the sheet.
    final double keyboard = MediaQuery.viewInsetsOf(context).bottom;
    final double topInset = MediaQuery.paddingOf(context).top;
    final double availableHeight =
        MediaQuery.sizeOf(context).height - keyboard - topInset;
    final double maxSheetHeight =
        availableHeight > 360 ? availableHeight * 0.86 : availableHeight;

    final String? path = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (BuildContext sheetContext) {
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxSheetHeight),
          child: GlassContainer(
            surface: AuraGlassSurface.floating,
            radius: 28,
            margin: const EdgeInsets.symmetric(horizontal: AuraSpace.md),
            padding: EdgeInsets.zero,
            child: SafeArea(
              top: false,
              left: false,
              right: false,
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  AuraSpace.lg,
                  AuraSpace.md,
                  AuraSpace.lg,
                  AuraSpace.lg + keyboard,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Semantics(
                      label: 'Drag handle',
                      hint: 'Swipe down to dismiss',
                      button: true,
                      child: Center(
                        child: Container(
                          width: 38,
                          height: 4,
                          decoration: BoxDecoration(
                            color: palette.border.withValues(
                              alpha: (palette.borderAlpha ?? 0.16) + 0.16,
                            ),
                            borderRadius:
                                BorderRadius.circular(AuraRadius.pill),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: AuraSpace.sm),
                    Text(
                      'MORE',
                      style: Theme.of(sheetContext).textTheme.labelMedium,
                    ),
                    const SizedBox(height: AuraSpace.xs),
                    for (final AuraDestination destination in others)
                      _SheetTile(
                        destination: destination,
                        selected: location == destination.path,
                        onTap: () =>
                            Navigator.of(sheetContext).pop(destination.path),
                      ),
                    const SizedBox(height: AuraSpace.xs),
                    Text(
                      '${AppInfo.name} v${AppInfo.version} - ${AppInfo.phase}',
                      style: Theme.of(sheetContext).textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    // Returning the path avoids racing navigation against modal teardown.
    if (path != null && context.mounted) context.go(path);
  }
}

/// Adds a restrained violet halo behind the active glyph without changing the
/// Forui item's icon size, padding or label spacing. The shadow does not affect
/// layout, so touch targets and capsule dimensions stay exactly as they were.
class _NavIcon extends StatelessWidget {
  const _NavIcon(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final Widget glyph = Icon(icon);
    final bool selected = FBottomNavigationBarData.of(context).selected;
    if (!selected) return glyph;

    final Color accent =
        IconTheme.of(context).color ?? AuraPaletteTheme.of(context).primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: accent.withValues(alpha: 0.24),
            blurRadius: 10,
            spreadRadius: 1,
          ),
        ],
      ),
      child: glyph,
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
    final AuraPalette palette = AuraPaletteTheme.of(context);
    return ListTile(
      leading: Icon(
        selected ? destination.selectedIcon : destination.icon,
        color: selected ? palette.secondary : palette.textSecondary,
        size: 20,
      ),
      title: Text(
        destination.label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: selected ? palette.textPrimary : palette.textSecondary,
            ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        size: 18,
        color: palette.textSecondary,
      ),
      onTap: onTap,
      minTileHeight: 48,
      contentPadding: const EdgeInsets.symmetric(horizontal: AuraSpace.xs),
      horizontalTitleGap: AuraSpace.sm,
      minLeadingWidth: 24,
      tileColor: selected ? palette.primary.withValues(alpha: 0.08) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AuraRadius.control),
      ),
    );
  }
}
