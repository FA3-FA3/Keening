import 'package:flutter/material.dart';

import '../widgets/hero_section.dart';
import '../widgets/login_button.dart';

/// Landing page. Overlays a Log In entry point in the top-right corner,
/// leading into the authenticated dashboard.
class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const HeroSection(),
        const Positioned(top: 16, right: 16, child: LoginButton()),
      ],
    );
  }
}
