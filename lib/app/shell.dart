import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets.dart';
import '../features/drawer/app_drawer.dart';
import '../features/workout/workout_button.dart';

/// The three tabs, with the drawer and the Start/Resume button above them.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: shellScaffoldKey,
      drawer: const AppDrawer(),
      body: shell,
      floatingActionButton: const WorkoutButton(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) =>
            shell.goBranch(index, initialLocation: index == shell.currentIndex),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.history), label: 'Log'),
          NavigationDestination(
            icon: Icon(Icons.fitness_center),
            label: 'Routines',
          ),
          NavigationDestination(
            icon: Icon(Icons.bar_chart_rounded),
            label: 'Statistics',
          ),
        ],
      ),
    );
  }
}
