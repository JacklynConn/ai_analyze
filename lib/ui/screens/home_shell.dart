import 'package:material_ui/material_ui.dart';

import '../../core/theme.dart';
import 'chart_screen.dart';
import 'dashboard_screen.dart';
import 'news_screen.dart';
import 'settings_screen.dart';
import 'signals_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  static const List<String> _titles = <String>[
    'Gold desk',
    'Chart',
    'Signals',
    'News',
    'Settings',
  ];

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      DashboardScreen(onOpenChart: () => setState(() => _index = 1)),
      const ChartScreen(),
      const SignalsScreen(),
      const NewsScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            Text(_titles[_index]),
            const SizedBox(width: 8),
            if (_index == 0)
              const Text(
                '· XAUUSD AI',
                style: TextStyle(color: AppColors.gold, fontSize: 13, fontWeight: FontWeight.w600),
              ),
          ],
        ),
      ),
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: const <BottomNavigationBarItem>[
          BottomNavigationBarItem(icon: Icon(Icons.insights_rounded), label: 'Market'),
          BottomNavigationBarItem(icon: Icon(Icons.candlestick_chart_rounded), label: 'Chart'),
          BottomNavigationBarItem(icon: Icon(Icons.radar_rounded), label: 'Signals'),
          BottomNavigationBarItem(icon: Icon(Icons.public_rounded), label: 'News'),
          BottomNavigationBarItem(icon: Icon(Icons.tune_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
