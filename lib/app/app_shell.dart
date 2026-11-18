import 'package:aura_hub/app/shell/app_top_bar.dart';
import 'package:aura_hub/app/shell/aura_sidebar.dart';
import 'package:aura_hub/app/shell/mobile_bottom_bar.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

class AppShell extends StatelessWidget {
  const AppShell({
    super.key,
    required this.location,
    required this.child,
  });

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool mobile = width < AuraBreakpoints.mobile;
    final bool compactNav = width < AuraBreakpoints.desktop;

    return _ShellBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: mobile
            ? Column(
                children: <Widget>[
                  AppTopBar(location: location),
                  Expanded(child: child),
                  MobileBottomBar(location: location),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  AnimatedContainer(
                    duration: AuraMotion.of(context, AuraMotion.slow),
                    curve: AuraMotion.standard,
                    width: compactNav ? 80 : 272,
                    child: AuraSidebar(
                      location: location,
                      expanded: !compactNav,
                    ),
                  ),
                  const VerticalDivider(width: 1, color: AuraColors.border),
                  Expanded(
                    child: Column(
                      children: <Widget>[
                        AppTopBar(location: location),
                        Expanded(child: child),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _ShellBackground extends StatelessWidget {
  const _ShellBackground({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: IgnorePointer(
              child: Stack(
                children: <Widget>[
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            AuraColors.background,
                            AuraColors.backgroundDeep,
                            Color(0xFF060910),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -300,
                    right: -200,
                    child: _ambientOrb(820, AuraGlass.ambientBlue),
                  ),
                  Positioned(
                    bottom: -360,
                    left: -240,
                    child: _ambientOrb(760, AuraGlass.ambientViolet),
                  ),
                  Positioned(
                    top: 180,
                    left: -320,
                    child: _ambientOrb(620, AuraGlass.ambientCyan),
                  ),
                  // Soft vertical sheen gives the backdrop a sense of depth
                  // without competing with the content above it.
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x07000000),
                            Color(0x00000000),
                            Color(0x0A000000),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }

  Widget _ambientOrb(double size, List<Color> colors) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      );
}
