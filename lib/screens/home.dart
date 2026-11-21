import 'package:flutter/material.dart';
import '../i18n.dart';
import '../orders.dart';
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
  void initState() {
    super.initState();
    // a "new purchase order" notification was tapped while signed out: open the orders screen now
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (Orders.pendingOpen && app.loggedIn && app.isManager) {
        Orders.pendingOpen = false;
        Orders.open();
      }
    });
  }

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
    final dests = <(IconData, String)>[
      (Icons.point_of_sale, tr('nav_sell')),
      if (mgr) (Icons.inventory_2_outlined, tr('nav_products')),
      (Icons.receipt_long_outlined, tr('nav_sales')),
      if (mgr) (Icons.insights_outlined, tr('nav_today')),
      (Icons.settings_outlined, tr('nav_settings')),
    ];
    if (_tab >= pages.length) _tab = 0;
    return Scaffold(
      body: SafeArea(bottom: false, child: pages[_tab]),
      bottomNavigationBar: SafeArea(
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: JC.surface2.withOpacity(0.94),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: JC.gold.withOpacity(0.45)),
            boxShadow: [BoxShadow(color: JC.gold.withOpacity(0.12), blurRadius: 18)],
          ),
          child: Row(children: [
            for (var i = 0; i < dests.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _tab = i),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: i == _tab ? JC.gold.withOpacity(0.14) : Colors.transparent,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: i == _tab ? JC.gold.withOpacity(0.8) : Colors.transparent),
                    ),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (mgr && i == dests.length - 1)
                        ValueListenableBuilder<int>(
                          valueListenable: Orders.unseen,
                          builder: (_, n, __) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(dests[i].$1, size: 24, color: i == _tab ? JC.gold : JC.muted)),
                        )
                      else
                        Icon(dests[i].$1, size: 24, color: i == _tab ? JC.gold : JC.muted),
                      const SizedBox(height: 3),
                      Text(dests[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: i == _tab ? JC.gold : JC.muted)),
                    ]),
                  ),
                ),
              ),
          ]),
        ),
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
