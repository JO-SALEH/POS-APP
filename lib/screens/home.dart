import 'package:flutter/material.dart';
import '../i18n.dart';
import '../theme.dart';
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
    final pages = <Widget>[const SellScreen(), const ProductsScreen(), const SalesScreen(), const SettingsScreen()];
    return Scaffold(
      body: SafeArea(bottom: false, child: pages[_tab]),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          NavigationDestination(icon: const Icon(Icons.point_of_sale), label: tr('nav_sell')),
          NavigationDestination(icon: const Icon(Icons.inventory_2_outlined), label: tr('nav_products')),
          NavigationDestination(icon: const Icon(Icons.receipt_long_outlined), label: tr('nav_sales')),
          NavigationDestination(icon: const Icon(Icons.settings_outlined), label: tr('nav_settings')),
        ],
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
