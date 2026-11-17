import 'package:aura_hub/app/shell/app_top_bar.dart';
import 'package:aura_hub/app/shell/aura_sidebar.dart';
import 'package:aura_hub/app/shell/mobile_bottom_bar.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
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
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                AuraColors.background,
                AuraColors.backgroundDeep,
              ],
            ),
          ),
        ),
        Positioned(
          top: -280,
          right: -180,
          child: IgnorePointer(
            child: Container(
              width: 780,
              height: 780,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AuraColors.primary.withValues(alpha: 0.10),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -340,
          left: -220,
          child: IgnorePointer(
            child: Container(
              width: 720,
              height: 720,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: <Color>[
                    AuraColors.secondary.withValues(alpha: 0.07),
                    Color(0x00000000),
                  ],
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

