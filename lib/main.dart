import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'data/run_repository.dart';
import 'tracking/run_tracker.dart';
import 'ui/activity_screen.dart';
import 'ui/run/run_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repo = await RunRepository.open();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: repo),
        ChangeNotifierProvider(create: (_) => RunTracker(repo)),
      ],
      child: const CourviteApp(),
    ),
  );
}

class CourviteApp extends StatelessWidget {
  const CourviteApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Courvite',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      themeMode: ThemeMode.light,
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // Focus mode: no navigation while a run is being recorded.
    final running = context.select<RunTracker, bool>(
      (t) => t.state != TrackerState.idle,
    );
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          RunScreen(visible: _tab == 0),
          const ActivityScreen(),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
        child: running
            ? const SizedBox(width: double.infinity)
            : _NavBar(index: _tab, onSelect: (i) => setState(() => _tab = i)),
      ),
    );
  }
}

/// Black pill navigation with an electric-yellow selection.
class _NavBar extends StatelessWidget {
  const _NavBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    Widget item(int i, IconData icon, String label) {
      final selected = i == index;
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => onSelect(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutCubic,
            height: 52,
            decoration: BoxDecoration(
              color: selected ? AppColors.volt : Colors.transparent,
              borderRadius: BorderRadius.circular(26),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: selected ? AppColors.ink : Colors.white70,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: labelStyle(
                    color: selected ? AppColors.ink : Colors.white70,
                    size: 13,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: AppColors.canvas,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.ink,
              borderRadius: BorderRadius.circular(32),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 16,
                  color: Color(0x33000000),
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                item(0, Icons.bolt_rounded, 'RUN'),
                item(1, Icons.insights_rounded, 'ACTIVITY'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
