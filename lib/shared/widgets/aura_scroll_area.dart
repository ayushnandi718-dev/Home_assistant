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
    return Scrollbar(
      controller: _controller,
      child: SingleChildScrollView(
        controller: _controller,
        padding: widget.padding,
        child: widget.child,
      ),
    );
  }
}
