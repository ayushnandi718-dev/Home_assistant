import 'package:aura_hub/core/theme/aura_palette.dart';
import 'package:flutter/material.dart';

/// Edge-to-edge ambient backdrop shared by every AURA screen.
///
/// The decorative orbs are painted once in a [RepaintBoundary] and ignore
/// pointer events. They are visual only: no network, device or profile state is
/// inferred from the palette.
class AuraGradientBackground extends StatelessWidget {
  const AuraGradientBackground({
    super.key,
    required this.child,
    this.mobile = false,
  });

  final Widget child;

  /// Mobile uses larger, softer orbs to match the compact purple-glass design.
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final AuraPalette palette = AuraPaletteTheme.of(context);
    final double scale = mobile ? 1.18 : 1;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: RepaintBoundary(
            child: IgnorePointer(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: <Color>[
                            palette.background,
                            palette.backgroundDeep,
                            palette.backgroundEdge,
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: -300 * scale,
                    right: -200 * scale,
                    child: _orb(820 * scale, palette.ambientTopRight),
                  ),
                  Positioned(
                    bottom: -360 * scale,
                    left: -240 * scale,
                    child: _orb(760 * scale, palette.ambientBottomLeft),
                  ),
                  Positioned(
                    top: 180 * scale,
                    left: -320 * scale,
                    child: _orb(620 * scale, palette.ambientMidLeft),
                  ),
                  const Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: <Color>[
                            Color(0x05000000),
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

  Widget _orb(double size, List<Color> colors) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: colors),
        ),
      );
}
