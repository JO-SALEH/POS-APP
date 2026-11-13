import 'package:flutter/material.dart';
import '../i18n.dart';
import '../theme.dart';
import 'dashboard.dart';
import '../services.dart';
import 'products.dart';
import 'sales.dart';
import 'sell.dart';
import 'settings.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  static int _tab = 0; // survives the language-change rebuild

  @override
  Widget build(BuildContext context) {
    final mgr = app.isManager;
    final pages = <Widget>[
      const SellScreen(),
      if (mgr) const ProductsScreen(),
      const SalesScreen(),
      if (mgr) const DashboardScreen(),
      const SettingsScreen(),
    ];
    final dests = <NavigationDestination>[
      NavigationDestination(icon: const Icon(Icons.point_of_sale), label: tr('nav_sell')),
      if (mgr) NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), label: tr('nav_products')),
      NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), label: tr('nav_sales')),
      if (mgr) NavigationDestination(icon: const Icon(Icons.insights_outlined), label: tr('nav_today')),
      NavigationDestination(icon: const Icon(Icons.settings_outlined), label: tr('nav_settings')),
    ];
    if (_tab >= pages.length) _tab = 0;
    return Scaffold(
      body: SafeArea(bottom: false, child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: dests,
      ),
    );
  }
}

class PageTitle extends StatelessWidget {
  final String text;
  final List<Widget> actions;
  const PageTitle(this.text, {super.key, this.actions = const []});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
        child: Row(children: [
          Container(width: 4, height: 24, decoration: BoxDecoration(color: JC.gold, borderRadius: BorderRadius.circular(2))),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: JC.gold, fontSize: 20, fontWeight: FontWeight.w800))),
          ...actions,
        ]),
      );
}
