import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/workout_repository.dart';

/// Logs an open workout, and edits a finished one. An open workout also gets
/// the running clock, the rest timer, Finish and Discard, and a screen kept
/// awake. Every change is written to the database straight away.
class WorkoutEditorScreen extends ConsumerStatefulWidget {
  const WorkoutEditorScreen({super.key, required this.workoutId});
  final String workoutId;

  @override
  ConsumerState<WorkoutEditorScreen> createState() =>
      _WorkoutEditorScreenState();
}

class _WorkoutEditorScreenState extends ConsumerState<WorkoutEditorScreen> {
  bool _wakelockOn = false;
  bool _leaving = false;

  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);

  void _syncWakelock(bool wanted) {
    if (wanted == _wakelockOn) return;
    _wakelockOn = wanted;
    _setWakelock(wanted);
  }

  /// A screen that dims is a nuisance, so a failure here must not interrupt
  /// logging.
  static Future<void> _setWakelock(bool enable) async {
    try {
      await WakelockPlus.toggle(enable: enable);
    } on PlatformException catch (error) {
      debugPrint('Could not change the screen wakelock: $error');
    }
  }

  @override
  void dispose() {
    if (_wakelockOn) _setWakelock(false);
    super.dispose();
  }

  void _leave() {
    _leaving = true;
    if (mounted) context.pop();
  }

  Future<void> _finish(WorkoutDetail detail) async {
    if (detail.completedSets == 0) {
      final discard = await confirm(
        context,
        title: 'No sets completed',
        message: 'A workout needs at least one completed set. Discard it?',
        action: 'Discard',
        destructive: true,
      );
      if (discard) await _deleteAndLeave();
      return;
    }
    final incomplete = detail.incompleteSets;
    final ok = await confirm(
      context,
      title: 'Finish workout?',
      message: incomplete == 0
          ? null
          : '$incomplete ${incomplete == 1 ? 'set' : 'sets'} not completed '
                'will be removed.',
      action: 'Finish',
    );
    if (!ok) return;
    ref.read(restTimerProvider.notifier).stop();
    await _repo.finish(widget.workoutId);
    _leave();
  }

  Future<void> _discard() async {
    final ok = await confirm(
      context,
      title: 'Discard workout?',
      message: 'This removes the workout and everything logged in it.',
      action: 'Discard',
      destructive: true,
    );
    if (ok) await _deleteAndLeave();
  }

  Future<void> _deleteAndLeave() async {
    ref.read(restTimerProvider.notifier).stop();
    _leaving = true;
    await _repo.delete(widget.workoutId);
    if (mounted) context.pop();
  }

  Future<void> _rename(Workout workout) async {
    final name = await promptForText(
      context,
      title: 'Workout name',
      initial: workout.nameSnapshot,
    );
    if (name != null) await _repo.rename(workout.id, name);
  }

  Future<DateTime?> _pickDateTime(DateTime current) async {
    final local = current.toLocal();
    final day = await showDatePicker(
      context: context,
      initialDate: local,
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (day == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(local),
    );
    if (time == null) return null;
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  Future<void> _editStart(Workout workout) async {
    final start = await _pickDateTime(workout.startedAt);
    if (start == null) return;
    final finish = workout.finishedAt!;
    if (!start.isBefore(finish)) {
      _showError('The start has to be before the end.');
      return;
    }
    await _repo.updateTimes(workout.id, startedAt: start, finishedAt: finish);
  }

  Future<void> _editEnd(Workout workout) async {
    final finish = await _pickDateTime(workout.finishedAt!);
    if (finish == null) return;
    if (!workout.startedAt.isBefore(finish)) {
      _showError('The end has to be after the start.');
      return;
    }
    await _repo.updateTimes(
      workout.id,
      startedAt: workout.startedAt,
      finishedAt: finish,
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _addExercises(Workout workout) async {
    final ids = await context.push<List<String>>('/exercise-picker');
    if (ids != null && ids.isNotEmpty) {
      await _repo.addExercises(workout.id, ids);
    }
  }

  void _move(WorkoutDetail detail, int index, int delta) {
    final ids = [for (final e in detail.exercises) e.row.id];
    ids.insert(index + delta, ids.removeAt(index));
    _repo.reorderExercises(ids);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(workoutDetailProvider(widget.workoutId));
    final settings = ref.watch(settingsProvider);
    final detail = async.value;

    if (detail == null) {
      // Deleted out from under this screen, such as by a restore.
      if (async.hasValue && !_leaving) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_leaving) _leave();
        });
      }
      return const Scaffold();
    }

    final workout = detail.workout;
    final isOpen = workout.finishedAt == null;
    _syncWakelock(isOpen && settings.keepAwake);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(isOpen ? Icons.keyboard_arrow_down : Icons.arrow_back),
          tooltip: 'Back',
          onPressed: () => context.pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              workout.nameSnapshot,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18),
            ),
            if (isOpen)
              _ElapsedClock(start: workout.startedAt)
            else
              Text(
                'Editing past workout',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
        actions: [
          if (isOpen)
            TextButton(
              onPressed: () => _finish(detail),
              child: const Text('Finish'),
            ),
          PopupMenuButton<void>(
            tooltip: 'More',
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => _rename(workout),
                child: const Text('Rename'),
              ),
              if (isOpen)
                PopupMenuItem(onTap: _discard, child: const Text('Discard')),
              if (!isOpen) ...[
                PopupMenuItem(
                  onTap: () => _editStart(workout),
                  child: const Text('Change start time'),
                ),
                PopupMenuItem(
                  onTap: () => _editEnd(workout),
                  child: const Text('Change end time'),
                ),
              ],
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 32),
        children: [
          if (!isOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                '${DateFormat.yMMMEd().format(workout.startedAt.toLocal())}, '
                '${formatTimeRange(workout.startedAt.toLocal(), workout.finishedAt!.toLocal())}',
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
          for (final (index, exercise) in detail.exercises.indexed)
            _ExerciseCard(
              key: ValueKey(exercise.row.id),
              workout: workout,
              exercise: exercise,
              unit: settings.unit,
              restSeconds: settings.restSeconds,
              onMoveUp: index == 0 ? null : () => _move(detail, index, -1),
              onMoveDown: index == detail.exercises.length - 1
                  ? null
                  : () => _move(detail, index, 1),
              onMessage: _showError,
            ),
          const SizedBox(height: 4),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
            icon: const Icon(Icons.add),
            label: const Text('Add exercise'),
            onPressed: () => _addExercises(workout),
          ),
        ],
      ),
      bottomNavigationBar: isOpen ? const _RestBar() : null,
    );
  }
}

class _ElapsedClock extends StatefulWidget {
  const _ElapsedClock({required this.start});
  final DateTime start;

  @override
  State<_ElapsedClock> createState() => _ElapsedClockState();
}

class _ElapsedClockState extends State<_ElapsedClock> {
  late final Timer _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => setState(() {}),
    );
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Text(
      formatClock(DateTime.now().difference(widget.start)),
      style: const TextStyle(
        fontSize: 12,
        color: AppColors.textSecondary,
        fontFeatures: [FontFeature.tabularFigures()],
      ),
    );
  }
}

class _ExerciseCard extends ConsumerWidget {
  const _ExerciseCard({
    super.key,
    required this.workout,
    required this.exercise,
    required this.unit,
    required this.restSeconds,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onMessage,
  });

  final Workout workout;
  final WorkoutExerciseDetail exercise;
  final WeightUnit unit;
  final int restSeconds;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final void Function(String) onMessage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final previous =
        ref
            .watch(
              previousSetsProvider((
                exercise.exercise.id,
                workout.startedAt,
              )),
            )
            .value ??
        const <WorkoutSet>[];
    final repo = ref.read(workoutRepositoryProvider);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  exercise.exercise.name,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              PopupMenuButton<void>(
                tooltip: 'Exercise options',
                icon: const Icon(Icons.more_horiz, color: AppColors.accent),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    enabled: onMoveUp != null,
                    onTap: onMoveUp,
                    child: const Text('Move up'),
                  ),
                  PopupMenuItem(
                    enabled: onMoveDown != null,
                    onTap: onMoveDown,
                    child: const Text('Move down'),
                  ),
                  PopupMenuItem(
                    onTap: () => repo.removeExercise(exercise.row.id),
                    child: const Text('Remove'),
                  ),
                ],
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(right: 8, bottom: 4),
            child: _SetLayout(
              number: const _ColumnLabel('Set'),
              previous: const _ColumnLabel('Previous'),
              weight: _ColumnLabel(unit.label),
              reps: const _ColumnLabel('Reps'),
              done: const Icon(
                Icons.check,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final (index, set) in exercise.sets.indexed)
            Dismissible(
              key: ValueKey('dismiss-${set.id}'),
              direction: DismissDirection.endToStart,
              onDismissed: (_) => repo.deleteSet(set.id),
              background: Container(
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: 16),
                child: const Icon(Icons.delete_outline, color: AppColors.danger),
              ),
              child: _SetRow(
                key: ValueKey(set.id),
                number: index + 1,
                set: set,
                previous: index < previous.length ? previous[index] : null,
                unit: unit,
                workout: workout,
                restSeconds: restSeconds,
                onMessage: onMessage,
              ),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add set'),
              onPressed: () => repo.addSet(exercise.row.id),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColumnLabel extends StatelessWidget {
  const _ColumnLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
    );
  }
}

/// The columns shared by the header row and the set rows.
class _SetLayout extends StatelessWidget {
  const _SetLayout({
    required this.number,
    required this.previous,
    required this.weight,
    required this.reps,
    required this.done,
  });

  final Widget number;
  final Widget previous;
  final Widget weight;
  final Widget reps;
  final Widget done;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 28, child: number),
        Expanded(flex: 5, child: previous),
        const SizedBox(width: 4),
        Expanded(flex: 4, child: weight),
        const SizedBox(width: 6),
        Expanded(flex: 3, child: reps),
        SizedBox(width: 44, child: Center(child: done)),
      ],
    );
  }
}

class _SetRow extends ConsumerStatefulWidget {
  const _SetRow({
    super.key,
    required this.number,
    required this.set,
    required this.previous,
    required this.unit,
    required this.workout,
    required this.restSeconds,
    required this.onMessage,
  });

  final int number;
  final WorkoutSet set;
  final WorkoutSet? previous;
  final WeightUnit unit;
  final Workout workout;
  final int restSeconds;
  final void Function(String) onMessage;

  @override
  ConsumerState<_SetRow> createState() => _SetRowState();
}

class _SetRowState extends ConsumerState<_SetRow> {
  late final _weight = TextEditingController(text: _weightText(widget.set));
  late final _reps = TextEditingController(
    text: widget.set.reps?.toString() ?? '',
  );
  final _weightFocus = FocusNode();
  final _repsFocus = FocusNode();

  WorkoutRepository get _repo => ref.read(workoutRepositoryProvider);

  String _weightText(WorkoutSet set) =>
      set.weightKg == null ? '' : formatWeight(set.weightKg!, widget.unit);

  double? _parseWeight(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  @override
  void didUpdateWidget(_SetRow old) {
    super.didUpdateWidget(old);
    // Never rewrite a field while it's being typed in: the database value is
    // just an echo of the same keystrokes.
    if (!_weightFocus.hasFocus) {
      final text = _weightText(widget.set);
      if (_weight.text != text) _weight.text = text;
    }
    if (!_repsFocus.hasFocus) {
      final text = widget.set.reps?.toString() ?? '';
      if (_reps.text != text) _reps.text = text;
    }
  }

  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    super.dispose();
  }

  void _onWeightChanged(String text) {
    if (text.trim().isEmpty) {
      _repo.updateSetWeight(widget.set.id, null);
      return;
    }
    final value = _parseWeight(text);
    if (value != null) {
      _repo.updateSetWeight(widget.set.id, widget.unit.toKg(value));
    }
  }

  void _onRepsChanged(String text) {
    _repo.updateSetReps(widget.set.id, int.tryParse(text));
  }

  Future<void> _toggleDone() async {
    final set = widget.set;
    if (set.completedAt != null) {
      await _repo.uncompleteSet(set.id);
      return;
    }

    // An empty field takes the value from last time, shown as its hint.
    final typedWeight = _parseWeight(_weight.text);
    final weightKg = typedWeight != null
        ? widget.unit.toKg(typedWeight)
        : widget.previous?.weightKg ?? 0;
    final reps = int.tryParse(_reps.text) ?? widget.previous?.reps;
    if (reps == null || reps < 1) {
      widget.onMessage('Enter your reps first.');
      return;
    }

    HapticFeedback.lightImpact();
    FocusManager.instance.primaryFocus?.unfocus();
    final finishedAt = widget.workout.finishedAt;
    await _repo.completeSet(
      set.id,
      weightKg: weightKg,
      reps: reps,
      at: finishedAt ?? DateTime.now(),
    );
    if (finishedAt == null) {
      ref.read(restTimerProvider.notifier).start(widget.restSeconds);
    }
  }

  @override
  Widget build(BuildContext context) {
    final done = widget.set.completedAt != null;
    final previous = widget.previous;
    final previousWeight = previous?.weightKg == null
        ? null
        : formatWeight(previous!.weightKg!, widget.unit);

    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.only(right: 8, top: 3, bottom: 3),
      decoration: BoxDecoration(
        color: done ? AppColors.navPill.withValues(alpha: 0.55) : null,
        borderRadius: BorderRadius.circular(10),
      ),
      child: _SetLayout(
        number: Text(
          '${widget.number}',
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        previous: Text(
          previous == null
              ? '-'
              : '${previousWeight ?? 0} × ${previous.reps ?? 0}',
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
        ),
        weight: _SetField(
          label: 'Weight for set ${widget.number}',
          controller: _weight,
          focusNode: _weightFocus,
          hint: previousWeight,
          decimal: true,
          onChanged: _onWeightChanged,
        ),
        reps: _SetField(
          label: 'Reps for set ${widget.number}',
          controller: _reps,
          focusNode: _repsFocus,
          hint: previous?.reps?.toString(),
          decimal: false,
          onChanged: _onRepsChanged,
        ),
        done: IconButton(
          tooltip: done
              ? 'Mark set ${widget.number} not done'
              : 'Mark set ${widget.number} done',
          padding: EdgeInsets.zero,
          visualDensity: VisualDensity.compact,
          icon: Icon(
            done ? Icons.check_box : Icons.check_box_outline_blank,
            color: done ? AppColors.accent : AppColors.textSecondary,
          ),
          onPressed: _toggleDone,
        ),
      ),
    );
  }
}

class _SetField extends StatelessWidget {
  const _SetField({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.decimal,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? hint;
  final bool decimal;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        textAlign: TextAlign.center,
        textInputAction: TextInputAction.next,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(
            decimal ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]'),
          ),
          LengthLimitingTextInputFormatter(decimal ? 6 : 4),
        ],
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          filled: true,
          fillColor: Colors.black38,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// The countdown shown after a set is completed.
class _RestBar extends ConsumerStatefulWidget {
  const _RestBar();

  @override
  ConsumerState<_RestBar> createState() => _RestBarState();
}

class _RestBarState extends ConsumerState<_RestBar> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      final end = ref.read(restTimerProvider);
      if (end == null) return;
      if (!end.isAfter(DateTime.now())) {
        HapticFeedback.heavyImpact();
        ref.read(restTimerProvider.notifier).expire();
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final end = ref.watch(restTimerProvider);
    if (end == null) return const SizedBox.shrink();
    final controller = ref.read(restTimerProvider.notifier);
    return Material(
      color: AppColors.bar,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.timer_outlined, color: AppColors.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  formatClock(end.difference(DateTime.now())),
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: const TextStyle(
                    fontSize: 20,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              TextButton(
                onPressed: () => controller.adjust(-15),
                child: const Text('-15'),
              ),
              TextButton(
                onPressed: () => controller.adjust(15),
                child: const Text('+15'),
              ),
              TextButton(onPressed: controller.stop, child: const Text('Skip')),
            ],
          ),
        ),
      ),
    );
  }
}
