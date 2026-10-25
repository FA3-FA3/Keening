import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/app_colors.dart';

/// Site footer with home navigation.
class SiteFooter extends StatelessWidget {
  const SiteFooter({super.key});

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.navBackgroundOf(context),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Navigation',
          style: TextStyle(
            color: AppColors.navTextOf(context),
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => context.go('/'),
          child: Text(
            'Home',
            style: TextStyle(
              color: AppColors.navTextOf(context),
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
