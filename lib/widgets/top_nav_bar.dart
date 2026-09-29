import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../utils/app_colors.dart';

class _NavItem {
  const _NavItem(this.label, this.path);
  final String label;
  final String path;
}

const List<_NavItem> _navItems = [_NavItem('Home', '/')];

/// Site header: centered site name on top, with the tab row
/// (plain routes — no dropdowns) centered beneath. Lives inline at the top
/// of the scrollable page content (see [AppShell]) rather than pinned as an
/// app bar, so it scrolls away as soon as the page moves.
class TopNavBar extends StatelessWidget {
  const TopNavBar({super.key, required this.currentPath});

  final String currentPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 148),
      width: double.infinity,
      color: AppColors.navBackground,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Keening',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: AppColors.navBrand,
              fontSize: 26,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 28,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final item in _navItems)
                _NavTab(item: item, isActive: item.path == currentPath),
            ],
          ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.item, required this.isActive});

  final _NavItem item;
  final bool isActive;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => context.go(item.path),
      child: Text(
        item.label,
        style: TextStyle(
          color: AppColors.navText,
          fontSize: 15,
          fontWeight: isActive ? FontWeight.w400 : FontWeight.w300,
        ),
      ),
    );
  }
}
