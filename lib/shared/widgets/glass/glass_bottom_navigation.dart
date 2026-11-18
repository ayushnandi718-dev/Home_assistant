import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';

/// Glass bottom navigation used on narrow windows and tablet-sized layouts.
class GlassBottomNavigation extends StatelessWidget {
  const GlassBottomNavigation({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<NavigationDestination> destinations;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: GlassContainer(
        surface: AuraGlassSurface.chrome,
        radius: 0,
        blur: 16,
        fill: 0.62,
        padding: EdgeInsets.zero,
        showHighlight: true,
        child: NavigationBar(
          selectedIndex: selectedIndex,
          onDestinationSelected: onDestinationSelected,
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          indicatorColor: AuraColors.primary.withValues(alpha: 0.18),
          destinations: destinations,
        ),
      ),
    );
  }
}
