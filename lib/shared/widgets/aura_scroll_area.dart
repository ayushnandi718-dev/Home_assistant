import 'package:aura_hub/core/theme/aura_tokens.dart';
import 'package:flutter/material.dart';

/// Vertical scroll area with a desktop scrollbar whose controller is always
/// attached to its scroll view.
///
/// Keeping the controller here prevents "Scrollbar's ScrollController has no
/// ScrollPosition attached" errors while a page is entering or leaving during
/// a route transition.
class AuraScrollArea extends StatefulWidget {
  const AuraScrollArea({
    super.key,
    required this.child,
    this.padding,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  State<AuraScrollArea> createState() => _AuraScrollAreaState();
}

class _AuraScrollAreaState extends State<AuraScrollArea> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    EdgeInsetsGeometry? padding = widget.padding;
    if (MediaQuery.sizeOf(context).width < AuraBreakpoints.mobile) {
      final EdgeInsets resolved =
          (padding ?? EdgeInsets.zero).resolve(Directionality.of(context));
      padding = resolved.copyWith(
        bottom: resolved.bottom < mobileNavFadeHeight
            ? mobileNavFadeHeight
            : resolved.bottom,
      );
    }

    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        padding: padding,
        child: widget.child,
      ),
    );
  }
}
