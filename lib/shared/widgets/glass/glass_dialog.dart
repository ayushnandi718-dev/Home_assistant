import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';

/// Dialog shell with a strongly frosted body over the dimmed scrim.
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.child,
    this.width = 560,
    this.padding = const EdgeInsets.all(AuraSpace.xl),
  });

  final Widget child;
  final double width;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AuraSpace.lg,
        vertical: AuraSpace.lg,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width),
        child: GlassContainer(
          surface: AuraGlassSurface.floating,
          radius: AuraRadius.panel,
          padding: padding,
          shadows: const <BoxShadow>[
            BoxShadow(
              color: Color(0x66030810),
              blurRadius: 64,
              offset: Offset(0, 28),
            ),
          ],
          child: child,
        ),
      ),
    );
  }
}

/// Shows [child] in a [GlassDialog] using Material's standard dialog motion.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required Widget child,
  double width = 560,
  EdgeInsetsGeometry padding = const EdgeInsets.all(AuraSpace.xl),
}) {
  return showDialog<T>(
    context: context,
    builder: (BuildContext context) => GlassDialog(
      width: width,
      padding: padding,
      child: child,
    ),
  );
}
