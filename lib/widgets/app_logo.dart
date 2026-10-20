import 'package:flutter/material.dart';

/// The Keening droplet (the same picture as the browser tab's icon).
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => Image.asset(
    'assets/images/logo.png',
    height: height,
    filterQuality: FilterQuality.none,
    semanticLabel: 'Keening',
  );
}
