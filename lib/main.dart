import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'l10n.dart';
import 'screens/panels_screen.dart';
import 'state/app_state.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final state = AppState();
  await state.load();
  runApp(ChangeNotifierProvider.value(value: state, child: const XuiManagerApp()));
}

class XuiManagerApp extends StatelessWidget {
  const XuiManagerApp({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    return MaterialApp(
      title: 'XUI Manager',
      debugShowCheckedModeBanner: false,
      locale: state.locale,
      supportedLocales: S.supportedLocales,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      themeMode: state.themeMode,
      theme: buildTheme(Brightness.light, state.style),
      darkTheme: buildTheme(Brightness.dark, state.style),
      home: const PanelsScreen(),
    );
  }
}
