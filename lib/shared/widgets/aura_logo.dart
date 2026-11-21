import 'package:flutter/material.dart';

/// AURA brand mark supplied by the project artwork.
///
/// The same artwork is used for the Android launcher icon and the in-app mark,
/// so the app identity stays consistent across Android, splash and shell.
class AuraLogo extends StatelessWidget {
  const AuraLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/images/aura_logo.png',
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
        excludeFromSemantics: true,
      ),
    );
  }
}
