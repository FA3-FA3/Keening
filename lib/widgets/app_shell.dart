import 'package:flutter/material.dart';

import '../utils/app_colors.dart';
import 'site_footer.dart';
import 'top_nav_bar.dart';

/// Wraps every page with [TopNavBar] and [SiteFooter] inline in the scroll
/// flow — the header scrolls out of view as soon as you move away from the
/// top of the page, and the footer only comes into view once you reach the
/// bottom, rather than either being permanently pinned on screen.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.currentPath, required this.child});

  final String currentPath;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background(context),
      body: SingleChildScrollView(
        child: Column(
          children: [
            TopNavBar(currentPath: currentPath),
            child,
            const SiteFooter(),
          ],
        ),
      ),
    );
  }
}
