import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db.dart';
import 'i18n.dart';
import 'lan.dart';
import 'orders.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'screens/orders.dart';
import 'services.dart';
import 'theme.dart';

/// Lets a tapped notification open a screen from outside the widget tree.
final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: JC.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  await Db.db; // opens + creates the local database (fully offline)
  await app.init();
  await Orders.load(); // purchase orders already on the phone
  Orders.onOpen = () => navKey.currentState?.push(MaterialPageRoute<void>(builder: (_) => const OrdersScreen()));
  await Notifier.init(); // the "new purchase order" notification (never throws)
  runApp(const JoApp());
  Lan.startAuto(); // quiet background sync with the PC (only when paired)
  if (Notifier.launchedByNotification) WidgetsBinding.instance.addPostFrameCallback((_) => Orders.open());
}

class JoApp extends StatelessWidget {
  const JoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'JØ PHARMA MOBILE',
        navigatorKey: navKey,
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        builder: (c, child) => Directionality(
          textDirection: L.ar ? TextDirection.rtl : TextDirection.ltr,
          child: AppBackground(child: child!),
        ),
        // The key forces a rebuild of the whole tree when the language changes.
        home: KeyedSubtree(
          key: ValueKey('${app.lang}-${app.loggedIn}'),
          child: app.loggedIn ? const HomeShell() : const LoginScreen(),
        ),
      ),
    );
  }
}
