import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../workout/workout_button.dart';

class RoutinePreviewScreen extends ConsumerWidget {
  const RoutinePreviewScreen({super.key, required this.routineId});
  final String routineId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(routineDetailProvider(routineId)).value;
    final hasOpenWorkout = ref.watch(openWorkoutProvider).value != null;
    final exercises = detail?.exercises ?? const [];
    final gymNames = ref.watch(gymNamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.routine.name ?? ''),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => context.push('/routine-editor?id=$routineId'),
          ),
        ],
      ),
      body: exercises.isEmpty
          ? const EmptyState(
              icon: Icons.fitness_center,
              title: 'No exercises',
              message: 'Edit this routine to add exercises.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final item = exercises[index];
                final sets = item.row.targetSets;
                return GroupedTile(
                  index: index,
                  count: exercises.length,
                  title: Text(
                    exerciseLabel(
                      item.exercise.name,
                      gymNames[item.exercise.gymId],
                    ),
                  ),
                  subtitle: Text(item.exercise.category),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '$sets ${sets == 1 ? 'set' : 'sets'}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            onPressed: hasOpenWorkout || detail == null
                ? null
                : () => startRoutineWorkout(context, ref, routineId),
            child: Text(
              hasOpenWorkout
                  ? 'Finish your open workout first'
                  : 'Start Workout',
            ),
          ),
        ),
      ),
    );
  }
}
