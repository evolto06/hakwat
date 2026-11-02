import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/drawer/backup_screen.dart';
import '../features/drawer/bodyweight_screen.dart';
import '../features/drawer/settings_screen.dart';
import '../features/exercises/exercise_library_screen.dart';
import '../features/exercises/exercise_picker_screen.dart';
import '../features/exercises/gyms_screen.dart';
import '../features/log/log_screen.dart';
import '../features/log/workout_detail_screen.dart';
import '../features/routines/routine_editor_screen.dart';
import '../features/routines/routine_preview_screen.dart';
import '../features/routines/routines_screen.dart';
import '../features/stats/stat_detail_screen.dart';
import '../features/stats/stats_screen.dart';
import '../features/workout/workout_editor_screen.dart';
import 'shell.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = _createRouter();
  ref.onDispose(router.dispose);
  return router;
});

GoRouter _createRouter() => GoRouter(
  initialLocation: '/log',
  routes: [
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => AppShell(shell: shell),
      branches: [
        StatefulShellBranch(
          routes: [GoRoute(path: '/log', builder: (_, _) => const LogScreen())],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/routines',
              builder: (_, _) => const RoutinesScreen(),
            ),
          ],
        ),
        StatefulShellBranch(
          routes: [
            GoRoute(path: '/stats', builder: (_, _) => const StatsScreen()),
          ],
        ),
      ],
    ),
    // The workout screen slides up over the tabs, matching the chevron on the
    // Start/Resume button.
    GoRoute(
      path: '/workout/:id',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: WorkoutEditorScreen(workoutId: state.pathParameters['id']!),
        transitionsBuilder: (context, animation, _, child) => SlideTransition(
          position: animation.drive(
            Tween(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).chain(CurveTween(curve: Curves.easeOutCubic)),
          ),
          child: child,
        ),
      ),
    ),
    GoRoute(
      path: '/history/:id',
      builder: (_, state) =>
          WorkoutDetailScreen(workoutId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/routine/:id',
      builder: (_, state) =>
          RoutinePreviewScreen(routineId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/routine-editor',
      builder: (_, state) =>
          RoutineEditorScreen(routineId: state.uri.queryParameters['id']),
    ),
    GoRoute(
      path: '/exercise-picker',
      builder: (_, _) => const ExercisePickerScreen(),
    ),
    GoRoute(
      path: '/exercises',
      builder: (_, _) => const ExerciseLibraryScreen(),
    ),
    GoRoute(path: '/gyms', builder: (_, _) => const GymsScreen()),
    GoRoute(path: '/bodyweight', builder: (_, _) => const BodyweightScreen()),
    GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
    GoRoute(path: '/backup', builder: (_, _) => const BackupScreen()),
    GoRoute(
      path: '/stat/:name',
      builder: (_, state) =>
          OverallStatScreen(statName: state.pathParameters['name']!),
    ),
    GoRoute(
      path: '/category/:name',
      builder: (_, state) =>
          CategoryStatScreen(category: state.pathParameters['name']!),
    ),
  ],
);
