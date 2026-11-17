import 'package:material_ui/material_ui.dart';

import 'core/theme.dart';
import 'ui/screens/home_shell.dart';

class XauusdAiTraderApp extends StatelessWidget {
  const XauusdAiTraderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'XAUUSD AI Trader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      home: const HomeShell(),
    );
  }
}
