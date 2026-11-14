import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'db.dart';
import 'i18n.dart';
import 'lan.dart';
import 'screens/home.dart';
import 'screens/login.dart';
import 'services.dart';
import 'theme.dart';

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
  runApp(const JoApp());
  Lan.startAuto(); // quiet background sync with the PC (only when paired)
}

class JoApp extends StatelessWidget {
  const JoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: app,
      builder: (context, _) => MaterialApp(
        title: 'JØ PHARMA MOBILE',
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
