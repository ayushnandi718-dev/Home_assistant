import 'package:aura_hub/core/theme/aura_glass.dart';
import 'package:aura_hub/core/theme/aura_motion.dart';
import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:aura_hub/shared/widgets/glass/glass_container.dart';
import 'package:flutter/material.dart';

/// Dialog shell with a strongly frosted body over the dimmed scrim.
///
/// [keyboardAware] is used by authentication dialogs whose controls must stay
/// reachable while Android's IME is open. Material's [Dialog] already adds
/// [MediaQuery.viewInsets] to its outer padding, so this shell only uses the
/// inset to bound the content height; it must not add it a second time.
class GlassDialog extends StatelessWidget {
  const GlassDialog({
    super.key,
    required this.child,
    this.width = 560,
    this.padding = const EdgeInsets.all(AuraSpace.xl),
    this.keyboardAware = false,
  });

  final Widget child;
  final double width;
  final EdgeInsetsGeometry padding;
  final bool keyboardAware;

  @override
  Widget build(BuildContext context) {
    final EdgeInsets viewPadding = MediaQuery.paddingOf(context);
    final double keyboardInset =
        keyboardAware ? MediaQuery.viewInsetsOf(context).bottom : 0;
    final EdgeInsets dialogInsetPadding = keyboardAware
        ? EdgeInsets.fromLTRB(
            AuraSpace.lg,
            AuraSpace.lg + viewPadding.top,
            AuraSpace.lg,
            AuraSpace.lg + viewPadding.bottom,
          )
        : const EdgeInsets.symmetric(
            horizontal: AuraSpace.lg,
            vertical: AuraSpace.lg,
          );

    // The Dialog subtracts viewInsets from its own constraints. Subtract the
    // system bars here as well so a modal can never sit under gesture nav.
    final double maxContentHeight = MediaQuery.sizeOf(context).height -
        keyboardInset -
        viewPadding.vertical -
        (AuraSpace.lg * 2);
    final BoxConstraints contentConstraints = keyboardAware
        ? BoxConstraints(
            maxHeight: maxContentHeight > 220 ? maxContentHeight : 220)
        : const BoxConstraints();

    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: dialogInsetPadding,
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          // Dialog only caps the maximum width; without an explicit width the
          // glass body shrinks to its content and the studio footer wraps oddly.
          final double effectiveWidth =
              constraints.maxWidth.isFinite && constraints.maxWidth < width
                  ? constraints.maxWidth
                  : width;
          final Widget glassBody = GlassContainer(
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
            child: keyboardAware
                ? SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    child: child,
                  )
                : child,
          );

          return AnimatedContainer(
            duration: keyboardAware
                ? AuraMotion.of(context, AuraMotion.medium)
                : Duration.zero,
            curve: AuraMotion.enter,
            constraints: contentConstraints,
            child: SizedBox(width: effectiveWidth, child: glassBody),
          );
        },
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
  bool keyboardAware = false,
  bool barrierDismissible = true,
  Color? barrierColor,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    builder: (BuildContext context) => GlassDialog(
      width: width,
      padding: padding,
      keyboardAware: keyboardAware,
      child: child,
    ),
  );
}
