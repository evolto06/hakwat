import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/library_repositories.dart';
import '../../data/seed_exercises.dart';
import 'gyms_screen.dart';

/// Adds a custom exercise, or edits [existing]. [template] starts a new exercise
/// from another one, which is how a generic machine gets a copy at a gym.
/// Returns the exercise's ID once saved, or null if cancelled.
Future<String?> showExerciseForm(
  BuildContext context, {
  Exercise? existing,
  Exercise? template,
  String? initialCategory,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _ExerciseForm(
      existing: existing,
      template: template,
      initialCategory: initialCategory,
    ),
  );
}

class _ExerciseForm extends ConsumerStatefulWidget {
  const _ExerciseForm({this.existing, this.template, this.initialCategory});
  final Exercise? existing;
  final Exercise? template;
  final String? initialCategory;

  @override
  ConsumerState<_ExerciseForm> createState() => _ExerciseFormState();
}

class _ExerciseFormState extends ConsumerState<_ExerciseForm> {
  late final Exercise? _source = widget.existing ?? widget.template;
  late final _name = TextEditingController(text: _source?.name);
  late String _category =
      _source?.category ?? widget.initialCategory ?? categories.first;
  late bool _isMachine = _source?.isMachine ?? false;
  late String? _gymId = widget.existing?.gymId;
  late WeightMode? _mode = _source?.weightMode;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _setMachine(bool isMachine) {
    setState(() {
      _isMachine = isMachine;
      if (!isMachine) {
        _gymId = null;
        if (_mode == WeightMode.pin) _mode = null;
      }
    });
  }

  Future<void> _addGym() async {
    final id = await createGym(context, ref);
    if (id != null && mounted) setState(() => _gymId = id);
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
        id = await repo.create(
          name,
          _category,
          isMachine: _isMachine,
          gymId: _gymId,
          weightMode: _mode,
        );
      } else {
        await repo.edit(
          existing.id,
          name,
          _category,
          isMachine: _isMachine,
          gymId: _gymId,
          weightMode: _mode,
        );
        id = existing.id;
      }
      if (mounted) Navigator.pop(context, id);
    } on DuplicateExerciseName {
      setState(
        () => _error = _gymId == null
            ? 'An exercise with this name already exists'
            : 'This gym already has an exercise with this name',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final gyms = ref.watch(gymsProvider).value ?? const <Gym>[];
    final appUnit = ref.watch(settingsProvider).unit;
    final title = widget.existing != null
        ? 'Edit exercise'
        : widget.template != null
        ? 'Add to a gym'
        : 'New exercise';

    return AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _name,
              autofocus: _source == null,
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
            const SizedBox(height: 16),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Free weight')),
                ButtonSegment(value: true, label: Text('Machine')),
              ],
              selected: {_isMachine},
              onSelectionChanged: (value) => _setMachine(value.single),
            ),
            if (_isMachine) ...[
              const SizedBox(height: 16),
              // Keyed so picking a just-created gym updates the shown value.
              DropdownButtonFormField<String?>(
                key: ValueKey('gym-$_gymId-${gyms.length}'),
                // The list can lag behind a gym that was just created.
                initialValue: gyms.any((g) => g.id == _gymId) ? _gymId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Gym'),
                items: [
                  const DropdownMenuItem(
                    value: null,
                    child: Text('Generic (no gym)'),
                  ),
                  for (final gym in gyms)
                    DropdownMenuItem(value: gym.id, child: Text(gym.name)),
                ],
                onChanged: (value) => setState(() => _gymId = value),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('New gym'),
                  onPressed: _addGym,
                ),
              ),
            ],
            const SizedBox(height: 16),
            DropdownButtonFormField<WeightMode?>(
              key: ValueKey('mode-$_isMachine'),
              initialValue: _mode,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Log weight in'),
              items: [
                DropdownMenuItem(
                  value: null,
                  child: Text('Default (${appUnit.label})'),
                ),
                for (final mode in WeightMode.values)
                  if (_isMachine || mode != WeightMode.pin)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
              ],
              onChanged: (value) => setState(() => _mode = value),
            ),
            if (_mode == WeightMode.pin) ...[
              const SizedBox(height: 12),
              PinEstimateNote(
                incrementLb: ref.watch(settingsProvider).pinIncrementLb,
              ),
            ],
          ],
        ),
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
