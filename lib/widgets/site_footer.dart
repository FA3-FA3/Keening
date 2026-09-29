import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/app_colors.dart';

/// Site footer with home navigation.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.navBackground,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Navigation',
          style: TextStyle(
            color: AppColors.navText,
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => context.go('/'),
          child: const Text(
            'Home',
            style: TextStyle(
              color: AppColors.navText,
              fontSize: 13,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
        const SizedBox(height: 6),
      ],
    ),
  );
}
