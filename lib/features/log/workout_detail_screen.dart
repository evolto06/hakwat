import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/workout_repository.dart';

/// A past workout, read-only. Edit opens it in the same screen used for
/// logging.
class WorkoutDetailScreen extends ConsumerWidget {
  const WorkoutDetailScreen({super.key, required this.workoutId});
  final String workoutId;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete workout?',
      message: 'This removes the workout and its sets from your history.',
      action: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    await ref.read(workoutRepositoryProvider).delete(workoutId);
    if (context.mounted) context.pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(workoutDetailProvider(workoutId)).value;
    final settings = ref.watch(settingsProvider);
    final unit = settings.unit;
    final gymNames = ref.watch(gymNamesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(detail?.workout.nameSnapshot ?? ''),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => context.push('/workout/$workoutId'),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _delete(context, ref),
          ),
        ],
      ),
      body: detail == null
          ? const SizedBox.shrink()
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                _SummaryHeader(
                  detail: detail,
                  unit: unit,
                  pinIncrementLb: settings.pinIncrementLb,
                ),
                const SizedBox(height: 16),
                for (final exercise in detail.exercises)
                  _ExerciseCard(
                    exercise: exercise,
                    unit: unitForMode(exercise.exercise.weightMode, unit),
                    gymName: gymNames[exercise.exercise.gymId],
                  ),
              ],
            ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({
    required this.detail,
    required this.unit,
    required this.pinIncrementLb,
  });
  final int pinIncrementLb;
  final WorkoutDetail detail;
  final WeightUnit unit;

  @override
  Widget build(BuildContext context) {
    final workout = detail.workout;
    final start = workout.startedAt.toLocal();
    final end = workout.finishedAt?.toLocal();
    var volumeKg = 0.0;
    var hasPinSets = false;
    for (final exercise in detail.exercises) {
      for (final set in exercise.sets) {
        if (set.completedAt != null) {
          final pin = set.pin;
          if (pin != null) hasPinSets = true;
          final weightKg = pin != null
              ? pinWeightKg(pin, pinIncrementLb)
              : set.weightKg ?? 0;
          volumeKg += weightKg * (set.reps ?? 0);
        }
      }
    }
    final timeRange = end == null
        ? DateFormat.jm().format(start)
        : formatTimeRange(start, end);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          DateFormat.yMMMMEEEEd().format(start),
          style: const TextStyle(fontSize: 16),
        ),
        const SizedBox(height: 4),
        Text(timeRange, style: const TextStyle(color: AppColors.textSecondary)),
        const SizedBox(height: 16),
        Row(
          children: [
            _Figure(
              label: 'Duration',
              value: end == null ? '-' : formatDuration(end.difference(start)),
            ),
            _Figure(label: 'Sets', value: '${detail.completedSets}'),
            _Figure(
              label: 'Volume',
              value:
                  '${formatCount(unit.fromKg(volumeKg).round())} ${unit.label}',
            ),
          ],
        ),
        if (hasPinSets) ...[
          const SizedBox(height: 12),
          PinEstimateNote(incrementLb: pinIncrementLb),
        ],
      ],
    );
  }
}

class _Figure extends StatelessWidget {
  const _Figure({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
          Text(value, style: const TextStyle(fontSize: 16)),
        ],
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  const _ExerciseCard({
    required this.exercise,
    required this.unit,
    required this.gymName,
  });
  final WorkoutExerciseDetail exercise;
  final WeightUnit unit;
  final String? gymName;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            exerciseLabel(exercise.exercise.name, gymName),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          for (final (index, set) in exercise.sets.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Text(
                      '${index + 1}',
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  ),
                  Text(
                    '${formatLoad(set.weightKg, set.pin, unit)} '
                    '× ${set.reps ?? 0}',
                    style: TextStyle(
                      color: set.completedAt == null
                          ? AppColors.textSecondary
                          : AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
