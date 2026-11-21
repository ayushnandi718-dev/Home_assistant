import 'package:aura_hub/shared/widgets/glass/glass_badge.dart';
import 'package:flutter/material.dart';

/// Backwards-compatible status pill, now rendered as a glass badge.
class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.showDot = true,
    this.dense = false,
  });

  final String label;
  final IconData? icon;
  final Color? color;
  final bool showDot;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return GlassStatusBadge(
      label: label,
      color: color,
      icon: icon,
      showDot: showDot,
      dense: dense,
    );
  }
}
