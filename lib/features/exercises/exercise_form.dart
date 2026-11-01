import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/database.dart';
import '../../data/library_repositories.dart';
import '../../data/seed_exercises.dart';

/// Adds a custom exercise, or edits [existing]. Returns the exercise's ID once
/// saved, or null if cancelled.
Future<String?> showExerciseForm(
  BuildContext context, {
  Exercise? existing,
  String? initialCategory,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) =>
        _ExerciseForm(existing: existing, initialCategory: initialCategory),
  );
}

class _ExerciseForm extends ConsumerStatefulWidget {
  const _ExerciseForm({this.existing, this.initialCategory});
  final Exercise? existing;
  final String? initialCategory;

  @override
  ConsumerState<_ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends ConsumerState<_ExerciseForm> {
  late final _name = TextEditingController(text: widget.existing?.name);
  late String _category =
      widget.existing?.category ?? widget.initialCategory ?? categories.first;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a name');
      return;
    }
    final repo = ref.read(exerciseRepositoryProvider);
    try {
      final existing = widget.existing;
      final String id;
      if (existing == null) {
        id = await repo.create(name, _category);
      } else {
        await repo.edit(existing.id, name, _category);
        id = existing.id;
      }
      if (mounted) Navigator.pop(context, id);
    } on DuplicateExerciseName {
      setState(() => _error = 'An exercise with this name already exists');
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'New exercise' : 'Edit exercise'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            autofocus: widget.existing == null,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Name', errorText: _error),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final category in categories)
                DropdownMenuItem(value: category, child: Text(category)),
            ],
            onChanged: (value) => setState(() => _category = value!),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
