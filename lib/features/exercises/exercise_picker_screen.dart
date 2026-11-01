import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/seed_exercises.dart';
import 'exercise_form.dart';

/// Search the library by name and category, and pick one or more exercises.
/// Pops with the chosen exercise IDs in the order they were tapped.
class ExercisePickerScreen extends ConsumerStatefulWidget {
  const ExercisePickerScreen({super.key});

  @override
  ConsumerState<ExercisePickerScreen> createState() =>
      _ExercisePickerScreenState();
}

class _ExercisePickerScreenState extends ConsumerState<ExercisePickerScreen> {
  final _selected = <String>[];
  String _query = '';
  String? _category;

  void _toggle(String id) {
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Future<void> _createExercise() async {
    final id = await showExerciseForm(context, initialCategory: _category);
    if (id != null && mounted) setState(() => _selected.add(id));
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final exercises = [
      for (final exercise in ref.watch(exercisesProvider).value ?? const [])
        if (exercise.archivedAt == null &&
            (_category == null || exercise.category == _category) &&
            exercise.name.toLowerCase().contains(query))
          exercise,
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add exercises'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'New exercise',
            onPressed: _createExercise,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SearchBar(
              hintText: 'Search',
              elevation: const WidgetStatePropertyAll(0),
              backgroundColor: const WidgetStatePropertyAll(AppColors.card),
              leading: const Icon(Icons.search),
              onChanged: (value) => setState(() => _query = value),
            ),
          ),
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final category in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: FilterChip(
                      label: Text(category),
                      selected: _category == category,
                      onSelected: (selected) => setState(
                        () => _category = selected ? category : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 16),
              itemCount: exercises.length,
              itemBuilder: (context, index) {
                final exercise = exercises[index];
                return CheckboxListTile(
                  value: _selected.contains(exercise.id),
                  title: Text(exercise.name),
                  subtitle: Text(exercise.category),
                  onChanged: (_) => _toggle(exercise.id),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selected.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  onPressed: () => context.pop(List<String>.of(_selected)),
                  child: Text(
                    'Add ${_selected.length} '
                    '${_selected.length == 1 ? 'exercise' : 'exercises'}',
                  ),
                ),
              ),
            ),
    );
  }
}
