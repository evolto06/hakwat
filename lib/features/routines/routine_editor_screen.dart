import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/library_repositories.dart';

class _EditorItem {
  _EditorItem(this.exercise, this.targetSets) : key = UniqueKey();
  final Exercise exercise;
  int targetSets;
  final Key key;
}

/// Creates a routine when [routineId] is null, and edits one otherwise. Changes
/// are held on this screen until Save.
class RoutineEditorScreen extends ConsumerStatefulWidget {
  const RoutineEditorScreen({super.key, this.routineId});
  final String? routineId;

  @override
  ConsumerState<RoutineEditorScreen> createState() =>
      _RoutineEditorScreenState();
}

class _RoutineEditorScreenState extends ConsumerState<RoutineEditorScreen> {
  final _name = TextEditingController();
  final _items = <_EditorItem>[];
  bool _loading = true;
  bool _dirty = false;
  bool _showNameError = false;

  @override
  void initState() {
    super.initState();
    _load();
    _name.addListener(_markDirtyOnNameChange);
  }

  String _loadedName = '';

  void _markDirtyOnNameChange() {
    if (_name.text != _loadedName && !_dirty) setState(() => _dirty = true);
  }

  Future<void> _load() async {
    final id = widget.routineId;
    if (id != null) {
      final detail = await ref
          .read(routineRepositoryProvider)
          .watchDetail(id)
          .first;
      if (!mounted) return;
      if (detail != null) {
        _loadedName = detail.routine.name;
        _name.text = _loadedName;
        _items.addAll([
          for (final item in detail.exercises)
            _EditorItem(item.exercise, item.row.targetSets),
        ]);
      }
    }
    setState(() => _loading = false);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _addExercises() async {
    final ids = await context.push<List<String>>('/exercise-picker');
    if (ids == null || ids.isEmpty || !mounted) return;
    final all = await ref.read(exerciseRepositoryProvider).watchAll().first;
    final byId = {for (final e in all) e.id: e};
    setState(() {
      for (final id in ids) {
        if (byId[id] case final exercise?) {
          _items.add(_EditorItem(exercise, 3));
        }
      }
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      setState(() => _showNameError = true);
      return;
    }
    final items = [
      for (final item in _items)
        RoutineItem(exerciseId: item.exercise.id, targetSets: item.targetSets),
    ];
    final repo = ref.read(routineRepositoryProvider);
    final id = widget.routineId;
    if (id == null) {
      await repo.create(name, items);
    } else {
      await repo.save(id, name, items);
    }
    if (!mounted) return;
    setState(() => _dirty = false);
    context.pop();
  }

  void _changeSets(_EditorItem item, int delta) {
    final next = item.targetSets + delta;
    if (next < 1 || next > 20) return;
    setState(() {
      item.targetSets = next;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final gymNames = ref.watch(gymNamesProvider);
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final discard = await confirm(
          context,
          title: 'Discard changes?',
          action: 'Discard',
          destructive: true,
        );
        if (discard && context.mounted) {
          setState(() => _dirty = false);
          context.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.routineId == null ? 'New routine' : 'Edit routine',
          ),
          actions: [
            TextButton(onPressed: _save, child: const Text('Save')),
            const SizedBox(width: 8),
          ],
        ),
        body: _loading
            ? const SizedBox.shrink()
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: TextField(
                      controller: _name,
                      textCapitalization: TextCapitalization.words,
                      decoration: InputDecoration(
                        labelText: 'Routine name',
                        errorText: _showNameError ? 'Enter a name' : null,
                      ),
                      onChanged: (_) {
                        if (_showNameError) {
                          setState(() => _showNameError = false);
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: ReorderableListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      buildDefaultDragHandles: false,
                      itemCount: _items.length,
                      onReorderItem: (from, to) => setState(() {
                        _items.insert(to, _items.removeAt(from));
                        _dirty = true;
                      }),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return Container(
                          key: item.key,
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: Icon(
                                    Icons.drag_handle,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  exerciseLabel(
                                    item.exercise.name,
                                    gymNames[item.exercise.gymId],
                                  ),
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove),
                                tooltip: 'Fewer sets',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _changeSets(item, -1),
                              ),
                              SizedBox(
                                width: 20,
                                child: Text(
                                  '${item.targetSets}',
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add),
                                tooltip: 'More sets',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => _changeSets(item, 1),
                              ),
                              IconButton(
                                icon: const Icon(Icons.close),
                                tooltip: 'Remove',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => setState(() {
                                  _items.remove(item);
                                  _dirty = true;
                                }),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                        ),
                        icon: const Icon(Icons.add),
                        label: const Text('Add exercises'),
                        onPressed: _addExercises,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
