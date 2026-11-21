import 'package:aura_hub/app/shell/app_top_bar.dart';
import 'package:aura_hub/app/shell/aura_sidebar.dart';
import 'package:aura_hub/app/shell/mobile_bottom_bar.dart';
import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/aura_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width;
    final bool mobile = width < AuraBreakpoints.mobile;
    final bool compactNav = width < AuraBreakpoints.desktop;

    final AuraPalette palette = AuraPaletteTheme.of(context);
    return AuraGradientBackground(
      mobile: mobile,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle(
          statusBarColor: palette.background,
          statusBarIconBrightness: Brightness.light,
          // Android 15+ draws edge-to-edge. Painting the system navigation bar
          // creates the full-width rectangular footer below the floating
          // capsule. Keep it transparent so the app background continues into
          // the gesture area while the gesture indicator stays interactive.
          systemNavigationBarColor: Colors.transparent,
          systemNavigationBarDividerColor: Colors.transparent,
          systemNavigationBarContrastEnforced: false,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          // Android uses adjustResize. Keeping the default resize behaviour lets
          // the shell shrink its body while the keyboard is open; the chat page
          // collapses its decorative chrome so the composer stays on screen.
          resizeToAvoidBottomInset: true,
          body: mobile
              ? Stack(
                  children: <Widget>[
                    Column(
                      children: <Widget>[
                        // The background stays edge-to-edge, but interactive
                        // chrome must sit below the status bar / display cutout.
                        SafeArea(
                          top: true,
                          bottom: false,
                          left: false,
                          right: false,
                          child: AppTopBar(location: location),
                        ),
                        Expanded(child: child),
                      ],
                    ),
                    // Painted above scrolling content but below the capsule.
                    // It has no border or divider, so it never becomes a footer.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: mobileNavFadeHeight,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                Colors.transparent,
                                palette.backgroundEdge,
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: MobileBottomBar(location: location),
                    ),
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
      ),
    );
  }
}
