import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/workout_repository.dart';

/// Starts a workout from a routine and opens it. If one is already open, that
/// one opens instead, because only one workout can be open at a time.
Future<void> startRoutineWorkout(
  BuildContext context,
  WidgetRef ref,
  String routineId,
) => _startAndOpen(
  context,
  () => ref.read(workoutRepositoryProvider).startFromRoutine(routineId),
);

Future<void> _startAndOpen(
  BuildContext context,
  Future<String> Function() start,
) async {
  String id;
  try {
    id = await start();
  } on WorkoutAlreadyOpen catch (open) {
    id = open.workoutId;
  }
  if (context.mounted) context.push('/workout/$id');
}

/// Reads "Start Workout" when nothing is open and "Resume Workout" otherwise.
class WorkoutButton extends ConsumerWidget {
  const WorkoutButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = ref.watch(openWorkoutProvider);
    final workout = open.value;
    return FloatingActionButton.extended(
      heroTag: null,
      icon: const Icon(Icons.keyboard_arrow_up),
      label: Text(workout == null ? 'Start Workout' : 'Resume Workout'),
      onPressed: () {
        if (workout != null) {
          context.push('/workout/${workout.id}');
        } else {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            useRootNavigator: true,
            showDragHandle: true,
            builder: (_) => const _StartSheet(),
          );
        }
      },
    );
  }
}

class _StartSheet extends ConsumerWidget {
  const _StartSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider).value ?? const [];
    final rootContext = GoRouter.of(context).routerDelegate.navigatorKey.currentContext!;

    void start(Future<String> Function() action) {
      Navigator.pop(context);
      _startAndOpen(rootContext, action);
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          ListTile(
            leading: const Icon(Icons.add, color: AppColors.accent),
            title: const Text('Empty workout'),
            onTap: () =>
                start(ref.read(workoutRepositoryProvider).startEmpty),
          ),
          if (routines.isNotEmpty) const Divider(),
          for (final routine in routines)
            ListTile(
              title: Text(routine.name),
              onTap: () => start(
                () => ref
                    .read(workoutRepositoryProvider)
                    .startFromRoutine(routine.id),
              ),
            ),
        ],
      ),
    );
  }
}
