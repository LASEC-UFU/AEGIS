import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../theme/app_theme.dart';
import 'data_screen.dart';
import 'evolution_screen.dart';
import 'results_screen.dart';
import 'agent_dashboard_screen.dart';
import 'about_screen.dart';

/// Main shell with responsive navigation (rail on desktop, bottom nav on mobile).
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  static const _destinations = [
    _NavItem(icon: LucideIcons.database, label: 'Data'),
    _NavItem(icon: LucideIcons.activity, label: 'Evolution'),
    _NavItem(icon: LucideIcons.brainCircuit, label: 'Agent'),
    _NavItem(icon: LucideIcons.fileBarChart, label: 'Results'),
    _NavItem(icon: LucideIcons.info, label: 'About'),
  ];

  static const _screens = [
    DataScreen(),
    EvolutionScreen(),
    AgentDashboardScreen(),
    ResultsScreen(),
    AboutScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768;
        final isExtraWide = constraints.maxWidth >= 1200;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                // Navigation rail
                _buildNavRail(isExtraWide),
                const VerticalDivider(width: 1),
                // Content
                Expanded(child: _screens[_selectedIndex]),
              ],
            ),
          );
        }

        // Mobile: bottom nav
        return Scaffold(
          body: _screens[_selectedIndex],
          bottomNavigationBar: _buildBottomNav(),
        );
      },
    );
  }

  Widget _buildNavRail(bool extended) {
    return NavigationRail(
      extended: extended,
      minExtendedWidth: 200,
      selectedIndex: _selectedIndex,
      onDestinationSelected: (i) => setState(() => _selectedIndex = i),
      leading: Tooltip(
        message: 'AEGIS — Adaptive Evolutionary Guided Identification System',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.accentSubtle,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  LucideIcons.dna,
                  color: AppColors.accent,
                  size: 20,
                ),
              ),
              if (extended) ...[
                const SizedBox(height: 8),
                Text(
                  'AEGIS',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  'v2.0',
                  style: TextStyle(color: AppColors.textTertiary, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
      destinations: _destinations
          .map(
            (d) => NavigationRailDestination(
              icon: Icon(d.icon),
              label: Text(d.label),
            ),
          )
          .toList(),
    );
  }

  Widget _buildBottomNav() {
    return BottomNavigationBar(
      currentIndex: _selectedIndex,
      onTap: (i) => setState(() => _selectedIndex = i),
      items: _destinations
          .map(
            (d) => BottomNavigationBarItem(icon: Icon(d.icon), label: d.label),
          )
          .toList(),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem({required this.icon, required this.label});
}
