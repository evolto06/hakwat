import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/seed_exercises.dart';
import 'exercise_form.dart';

class ExerciseLibraryScreen extends ConsumerStatefulWidget {
  const ExerciseLibraryScreen({super.key});

  @override
  ConsumerState<ExerciseLibraryScreen> createState() =>
      _ExerciseLibraryScreenState();
}

class _ExerciseLibraryScreenState extends ConsumerState<ExerciseLibraryScreen> {
  bool _showArchived = false;

  @override
  Widget build(BuildContext context) {
    final all = ref.watch(exercisesProvider).value ?? const <Exercise>[];
    final visible = [
      for (final exercise in all)
        if ((exercise.archivedAt != null) == _showArchived) exercise,
    ];
    final archivedCount = all.where((e) => e.archivedAt != null).length;

    return Scaffold(
      appBar: AppBar(
        title: Text(_showArchived ? 'Archived exercises' : 'Exercises'),
        actions: [
          if (_showArchived || archivedCount > 0)
            IconButton(
              icon: Icon(
                _showArchived ? Icons.unarchive : Icons.inventory_2_outlined,
              ),
              tooltip: _showArchived ? 'Show exercises' : 'Show archived',
              onPressed: () => setState(() => _showArchived = !_showArchived),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New exercise',
        onPressed: () => showExerciseForm(context),
        child: const Icon(Icons.add),
      ),
      body: visible.isEmpty
          ? EmptyState(
              icon: Icons.list_alt,
              title: _showArchived ? 'Nothing archived' : 'No exercises',
              message: _showArchived
                  ? 'Archived exercises show up here.'
                  : 'Tap + to add an exercise.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, listBottomPadding),
              children: [
                for (final category in {
                  ...categories,
                  ...visible.map((e) => e.category),
                })
                  ..._section(category, visible),
              ],
            ),
    );
  }

  List<Widget> _section(String category, List<Exercise> visible) {
    final items = visible.where((e) => e.category == category).toList();
    if (items.isEmpty) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 12, left: 4),
        child: Text(
          category,
          style: const TextStyle(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      for (final (index, exercise) in items.indexed)
        GroupedTile(
          index: index,
          count: items.length,
          title: Text(exercise.name),
          subtitle: _details(exercise),
          trailing: _Menu(exercise: exercise),
          onTap: () => showExerciseForm(context, existing: exercise),
        ),
    ];
  }

  /// The gym and logging mode, left out where there's nothing to say.
  Widget? _details(Exercise exercise) {
    final gymName = ref.watch(gymNamesProvider)[exercise.gymId];
    final parts = [
      ?gymName,
      if (gymName == null && exercise.isMachine) 'Machine',
      ?exercise.weightMode?.label,
    ];
    return parts.isEmpty ? null : Text(parts.join(' · '));
  }
}

class _Menu extends ConsumerWidget {
  const _Menu({required this.exercise});
  final Exercise exercise;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(exerciseRepositoryProvider);
    final archived = exercise.archivedAt != null;
    return PopupMenuButton<void>(
      tooltip: 'Exercise options',
      icon: const Icon(Icons.more_horiz, color: AppColors.accent),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: () => showExerciseForm(context, existing: exercise),
          child: const Text('Edit'),
        ),
        if (exercise.isMachine && exercise.gymId == null)
          PopupMenuItem(
            onTap: () => showExerciseForm(context, template: exercise),
            child: const Text('Add to a gym'),
          ),
        PopupMenuItem(
          onTap: () => archived
              ? repo.unarchive(exercise.id)
              : repo.archive(exercise.id),
          child: Text(archived ? 'Restore' : 'Archive'),
        ),
      ],
    );
  }
}
