import 'dart:math' as math;

import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/features/display/domain/display_preferences.dart';
import 'package:flutter/material.dart';

/// Native resolution of the ESP32-S3 4.3" panel (800x480, 5:3).
const double kPanelWidth = 800;
const double kPanelHeight = 480;
const double kPanelAspect = kPanelWidth / kPanelHeight;

/// Visual wallpaper picker: one thumbnail per wallpaper at the real panel
/// aspect ratio, replacing the plain text ChoiceChips.
class WallpaperGrid extends StatelessWidget {
  const WallpaperGrid({
    super.key,
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final PanelWallpaper selected;
  final Color accent;
  final ValueChanged<PanelWallpaper> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double gap = AuraSpace.sm;
        final int columns = constraints.maxWidth >= 640
            ? 4
            : constraints.maxWidth >= 420
                ? 3
                : 2;
        final double tileWidth =
            (constraints.maxWidth - gap * (columns - 1)) / columns;

        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            for (final PanelWallpaper wallpaper in PanelWallpaper.values)
              SizedBox(
                width: tileWidth,
                child: _WallpaperTile(
                  wallpaper: wallpaper,
                  accent: accent,
                  selected: wallpaper == selected,
                  onTap: () => onSelected(wallpaper),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.wallpaper,
    required this.accent,
    required this.selected,
    required this.onTap,
  });

  final PanelWallpaper wallpaper;
  final Color accent;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    final BorderRadius radius = BorderRadius.circular(AuraRadius.control);

    return Semantics(
      button: true,
      selected: selected,
      label: '${wallpaper.label} wallpaper',
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              decoration: BoxDecoration(
                borderRadius: radius,
                border: Border.all(
                  color: selected
                      ? accent
                      : AuraColors.textSecondary.withValues(alpha: 0.25),
                  width: selected ? 2 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: radius,
                child: AspectRatio(
                  aspectRatio: kPanelAspect,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: wallpaper.gradient,
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                      ),
                      CustomPaint(
                        painter: WallpaperPatternPainter(
                          pattern: wallpaper.pattern,
                          color: accent,
                        ),
                      ),
                      if (selected)
                        Positioned(
                          top: 6,
                          right: 6,
                          child: CircleAvatar(
                            radius: 10,
                            backgroundColor: accent,
                            child: const Icon(
                              Icons.check_rounded,
                              size: 14,
                              color: Colors.black,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              wallpaper.label,
              style: selected ? text.titleSmall : text.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Faint pattern overlay drawn on top of a wallpaper gradient.
/// Moved here (made public) so the grid and the live preview share it.
class WallpaperPatternPainter extends CustomPainter {
  const WallpaperPatternPainter({
    required this.pattern,
    required this.color,
  });

  final WallpaperPattern pattern;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (pattern == WallpaperPattern.none) return;
    final Color tint = color.withValues(alpha: 0.12);
    final Paint stroke = Paint()
      ..color = tint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    if (pattern == WallpaperPattern.dots) {
      final Paint dots = Paint()
        ..color = tint
        ..style = PaintingStyle.fill;
      for (double x = 12; x < size.width; x += 22) {
        for (double y = 12; y < size.height; y += 22) {
          canvas.drawCircle(Offset(x, y), 1.6, dots);
        }
      }
      return;
    }
    if (pattern == WallpaperPattern.rays) {
      final Offset center = size.center(Offset.zero);
      final double reach = math.max(size.width, size.height);
      for (int i = 0; i < 12; i++) {
        final double angle = i * 30 * math.pi / 180;
        canvas.drawLine(
          center,
          center + Offset(math.cos(angle), math.sin(angle)) * reach,
          stroke,
        );
      }
      return;
    }
    if (pattern == WallpaperPattern.grid) {
      for (double x = 0; x <= size.width; x += 28) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), stroke);
      }
      for (double y = 0; y <= size.height; y += 28) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), stroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant WallpaperPatternPainter oldDelegate) =>
      oldDelegate.pattern != pattern || oldDelegate.color != color;
}
