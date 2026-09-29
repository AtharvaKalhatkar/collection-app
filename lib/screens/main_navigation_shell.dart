import 'package:flutter/material.dart';
import '../utils/theme.dart';
import 'home_dashboard_screen.dart';
import 'collections_list_screen.dart';
import 'routes_shops_screen.dart';
import 'record_collection_screen.dart';
import 'add_shop_screen.dart';

class MainNavigationShell extends StatefulWidget {
  const MainNavigationShell({super.key});

  @override
  State<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends State<MainNavigationShell> {
  int _currentIndex = 0;

  void _navigateToTab(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    final screens = [
      HomeDashboardScreen(
        onNavigateToRoutes: () => _navigateToTab(2),
        onNavigateToCollections: () => _navigateToTab(1),
      ),
      const CollectionsListScreen(),
      const RoutesShopsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: screens,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: _navigateToTab,
        indicatorColor: AppTheme.primary.withValues(alpha: 0.1),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics, color: AppTheme.primary),
            label: 'Overview',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long, color: AppTheme.primary),
            label: 'Ledger',
          ),
          NavigationDestination(
            icon: Icon(Icons.storefront_outlined),
            selectedIcon: Icon(Icons.storefront, color: AppTheme.primary),
            label: 'Shops & Routes',
          ),
        ],
      ),
      floatingActionButton: _currentIndex == 2
          ? FloatingActionButton.extended(
              heroTag: 'main_shell_fab_store',
              backgroundColor: AppTheme.secondary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_business_outlined, size: 20),
              label: const Text('Add Store', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddShopScreen()),
                );
              },
            )
          : FloatingActionButton.extended(
              heroTag: 'main_shell_fab_record',
              backgroundColor: AppTheme.primary,
              foregroundColor: Colors.white,
              elevation: 2,
              icon: const Icon(Icons.add_circle_outline, size: 20),
              label: const Text('Record Payment', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const RecordCollectionScreen()),
                );
              },
            ),
    );
  }
}
