import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

const _uuid = Uuid();

/// A workout left this long after its last set is treated as forgotten.
const staleWorkoutAfter = Duration(hours: 3);

/// When a workout ends if it's finished at [now]. A workout that sat open for
/// hours ends at its last completed set, so it doesn't count as a ten-hour
/// session.
DateTime resolveFinishTime({
  required DateTime startedAt,
  required DateTime? lastCompletedAt,
  required DateTime now,
}) {
  final lastActivity = lastCompletedAt ?? startedAt;
  return now.difference(lastActivity) > staleWorkoutAfter ? lastActivity : now;
}

class WorkoutAlreadyOpen implements Exception {
  const WorkoutAlreadyOpen(this.workoutId);
  final String workoutId;
}

class SummaryLine {
  const SummaryLine(this.exerciseName, this.completedSets);
  final String exerciseName;
  final int completedSets;
}

class WorkoutSummary {
  const WorkoutSummary(this.workout, this.lines);
  final Workout workout;

  /// Exercises with at least one completed set, in workout order.
  final List<SummaryLine> lines;

  bool get isOpen => workout.finishedAt == null;

  Duration? get duration => workout.finishedAt?.difference(workout.startedAt);
}

class WorkoutExerciseDetail {
  const WorkoutExerciseDetail(this.row, this.exercise, this.sets);
  final WorkoutExercise row;
  final Exercise exercise;
  final List<WorkoutSet> sets;
}

class WorkoutDetail {
  const WorkoutDetail(this.workout, this.exercises);
  final Workout workout;
  final List<WorkoutExerciseDetail> exercises;

  int get completedSets => exercises.fold(
    0,
    (sum, e) => sum + e.sets.where((s) => s.completedAt != null).length,
  );

  int get incompleteSets => exercises.fold(
    0,
    (sum, e) => sum + e.sets.where((s) => s.completedAt == null).length,
  );
}

class WorkoutRepository {
  WorkoutRepository(this.db);
  final AppDatabase db;

  Stream<Workout?> watchOpen() =>
      (db.select(db.workouts)
            ..where((w) => w.finishedAt.isNull())
            ..limit(1))
          .watchSingleOrNull();

  /// All workouts, newest first.
  Stream<List<WorkoutSummary>> watchLog() {
    final query =
        db.select(db.workouts).join([
          leftOuterJoin(
            db.workoutExercises,
            db.workoutExercises.workoutId.equalsExp(db.workouts.id),
          ),
          leftOuterJoin(
            db.exercises,
            db.exercises.id.equalsExp(db.workoutExercises.exerciseId),
          ),
          leftOuterJoin(
            db.workoutSets,
            db.workoutSets.workoutExerciseId.equalsExp(db.workoutExercises.id),
          ),
        ])..orderBy([
          OrderingTerm.desc(db.workouts.startedAt),
          OrderingTerm.asc(db.workouts.id),
          OrderingTerm.asc(db.workoutExercises.sortOrder),
        ]);

    return query.watch().map((rows) {
      final workoutsById = <String, Workout>{};
      final countsByWorkout = <String, Map<String, (String, int)>>{};
      for (final row in rows) {
        final workout = row.readTable(db.workouts);
        workoutsById[workout.id] = workout;
        final counts = countsByWorkout.putIfAbsent(workout.id, () => {});
        final link = row.readTableOrNull(db.workoutExercises);
        final exercise = row.readTableOrNull(db.exercises);
        if (link == null || exercise == null) continue;
        final set = row.readTableOrNull(db.workoutSets);
        final done = set?.completedAt != null ? 1 : 0;
        final current = counts[link.id];
        counts[link.id] = (exercise.name, (current?.$2 ?? 0) + done);
      }
      return [
        for (final workout in workoutsById.values)
          WorkoutSummary(workout, [
            for (final (name, count) in countsByWorkout[workout.id]!.values)
              if (count > 0) SummaryLine(name, count),
          ]),
      ];
    });
  }

  Stream<WorkoutDetail?> watchDetail(String workoutId) {
    final workoutStream = (db.select(
      db.workouts,
    )..where((w) => w.id.equals(workoutId))).watchSingleOrNull();

    final query =
        db.select(db.workoutExercises).join([
            innerJoin(
              db.exercises,
              db.exercises.id.equalsExp(db.workoutExercises.exerciseId),
            ),
            leftOuterJoin(
              db.workoutSets,
              db.workoutSets.workoutExerciseId.equalsExp(
                db.workoutExercises.id,
              ),
            ),
            innerJoin(
              db.workouts,
              db.workouts.id.equalsExp(db.workoutExercises.workoutId),
            ),
          ])
          ..where(db.workoutExercises.workoutId.equals(workoutId))
          ..orderBy([
            OrderingTerm.asc(db.workoutExercises.sortOrder),
            OrderingTerm.asc(db.workoutSets.sortOrder),
          ]);

    // The join reads `workouts` too, so a change to the workout row (a rename
    // or new times) also re-emits here.
    return query.watch().asyncMap((rows) async {
      final workout = rows.isNotEmpty
          ? rows.first.readTable(db.workouts)
          : await workoutStream.first;
      if (workout == null) return null;

      final exercises = <String, Exercise>{};
      final links = <String, WorkoutExercise>{};
      final sets = <String, List<WorkoutSet>>{};
      for (final row in rows) {
        final link = row.readTable(db.workoutExercises);
        links[link.id] = link;
        exercises[link.id] = row.readTable(db.exercises);
        final group = sets.putIfAbsent(link.id, () => []);
        final set = row.readTableOrNull(db.workoutSets);
        if (set != null) group.add(set);
      }
      return WorkoutDetail(workout, [
        for (final link in links.values)
          WorkoutExerciseDetail(link, exercises[link.id]!, sets[link.id]!),
      ]);
    });
  }

  /// Completed sets from the last finished workout before [before] that
  /// included this exercise.
  Future<List<WorkoutSet>> previousSets(
    String exerciseId, {
    required DateTime before,
  }) async {
    final query =
        db.select(db.workoutSets).join([
            innerJoin(
              db.workoutExercises,
              db.workoutExercises.id.equalsExp(
                db.workoutSets.workoutExerciseId,
              ),
            ),
            innerJoin(
              db.workouts,
              db.workouts.id.equalsExp(db.workoutExercises.workoutId),
            ),
          ])
          ..where(
            db.workoutExercises.exerciseId.equals(exerciseId) &
                db.workouts.finishedAt.isNotNull() &
                db.workoutSets.completedAt.isNotNull(),
          )
          ..orderBy([
            OrderingTerm.desc(db.workouts.startedAt),
            OrderingTerm.asc(db.workoutExercises.sortOrder),
            OrderingTerm.asc(db.workoutSets.sortOrder),
          ]);

    final rows = await query.get();
    String? group;
    final result = <WorkoutSet>[];
    for (final row in rows) {
      if (!row.readTable(db.workouts).startedAt.isBefore(before)) continue;
      final set = row.readTable(db.workoutSets);
      group ??= set.workoutExerciseId;
      if (set.workoutExerciseId != group) break;
      result.add(set);
    }
    return result;
  }

  Future<String> startEmpty({DateTime? now}) =>
      _start(name: 'Workout', routineId: null, now: now, items: const []);

  Future<String> startFromRoutine(String routineId, {DateTime? now}) async {
    final routine = await (db.select(
      db.routines,
    )..where((r) => r.id.equals(routineId))).getSingle();
    final items =
        await (db.select(db.routineExercises)
              ..where((r) => r.routineId.equals(routineId))
              ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]))
            .get();
    return _start(
      name: routine.name,
      routineId: routineId,
      now: now,
      items: items,
    );
  }

  Future<String> _start({
    required String name,
    required String? routineId,
    required DateTime? now,
    required List<RoutineExercise> items,
  }) {
    return db.transaction(() async {
      final open = await (db.select(
        db.workouts,
      )..where((w) => w.finishedAt.isNull())).get();
      if (open.isNotEmpty) throw WorkoutAlreadyOpen(open.first.id);

      final workoutId = _uuid.v4();
      await db
          .into(db.workouts)
          .insert(
            WorkoutsCompanion.insert(
              id: workoutId,
              routineId: Value(routineId),
              nameSnapshot: name,
              startedAt: (now ?? DateTime.now()).toUtc(),
            ),
          );
      for (final (index, item) in items.indexed) {
        final linkId = _uuid.v4();
        await db
            .into(db.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                id: linkId,
                workoutId: workoutId,
                exerciseId: item.exerciseId,
                sortOrder: index,
              ),
            );
        for (var s = 0; s < item.targetSets; s++) {
          await db
              .into(db.workoutSets)
              .insert(
                WorkoutSetsCompanion.insert(
                  id: _uuid.v4(),
                  workoutExerciseId: linkId,
                  sortOrder: s,
                ),
              );
        }
      }
      return workoutId;
    });
  }

  Future<void> addExercises(String workoutId, List<String> exerciseIds) {
    return db.transaction(() async {
      var next = await _nextExerciseOrder(workoutId);
      for (final exerciseId in exerciseIds) {
        final linkId = _uuid.v4();
        await db
            .into(db.workoutExercises)
            .insert(
              WorkoutExercisesCompanion.insert(
                id: linkId,
                workoutId: workoutId,
                exerciseId: exerciseId,
                sortOrder: next++,
              ),
            );
        await db
            .into(db.workoutSets)
            .insert(
              WorkoutSetsCompanion.insert(
                id: _uuid.v4(),
                workoutExerciseId: linkId,
                sortOrder: 0,
              ),
            );
      }
    });
  }

  Future<int> _nextExerciseOrder(String workoutId) async {
    final rows = await (db.select(
      db.workoutExercises,
    )..where((e) => e.workoutId.equals(workoutId))).get();
    return rows.fold<int>(
      0,
      (next, e) => e.sortOrder >= next ? e.sortOrder + 1 : next,
    );
  }

  Future<void> removeExercise(String workoutExerciseId) => (db.delete(
    db.workoutExercises,
  )..where((e) => e.id.equals(workoutExerciseId))).go();

  /// Saves a new exercise order. [orderedIds] holds workout_exercise IDs.
  Future<void> reorderExercises(List<String> orderedIds) {
    return db.transaction(() async {
      for (final (index, id) in orderedIds.indexed) {
        await (db.update(db.workoutExercises)..where((e) => e.id.equals(id)))
            .write(WorkoutExercisesCompanion(sortOrder: Value(index)));
      }
    });
  }

  /// Adds a set, carrying over the last set's values as a starting point.
  Future<void> addSet(String workoutExerciseId) {
    return db.transaction(() async {
      final existing =
          await (db.select(db.workoutSets)
                ..where((s) => s.workoutExerciseId.equals(workoutExerciseId))
                ..orderBy([(s) => OrderingTerm.asc(s.sortOrder)]))
              .get();
      final last = existing.isEmpty ? null : existing.last;
      await db
          .into(db.workoutSets)
          .insert(
            WorkoutSetsCompanion.insert(
              id: _uuid.v4(),
              workoutExerciseId: workoutExerciseId,
              sortOrder: last == null ? 0 : last.sortOrder + 1,
              weightKg: Value(last?.weightKg),
              pin: Value(last?.pin),
              reps: Value(last?.reps),
            ),
          );
    });
  }

  Future<void> deleteSet(String setId) =>
      (db.delete(db.workoutSets)..where((s) => s.id.equals(setId))).go();

  Future<void> updateSetWeight(String setId, double? weightKg) =>
      (db.update(db.workoutSets)..where((s) => s.id.equals(setId))).write(
        WorkoutSetsCompanion(weightKg: Value(weightKg)),
      );

  Future<void> updateSetPin(String setId, int? pin) =>
      (db.update(db.workoutSets)..where((s) => s.id.equals(setId))).write(
        WorkoutSetsCompanion(pin: Value(pin)),
      );

  Future<void> updateSetReps(String setId, int? reps) =>
      (db.update(db.workoutSets)..where((s) => s.id.equals(setId))).write(
        WorkoutSetsCompanion(reps: Value(reps)),
      );

  /// Saves the set as done with either a weight or a pin, clearing the other.
  Future<void> completeSet(
    String setId, {
    double? weightKg,
    int? pin,
    required int reps,
    required DateTime at,
  }) => (db.update(db.workoutSets)..where((s) => s.id.equals(setId))).write(
    WorkoutSetsCompanion(
      weightKg: Value(pin == null ? weightKg : null),
      pin: Value(pin),
      reps: Value(reps),
      completedAt: Value(at.toUtc()),
    ),
  );

  Future<void> uncompleteSet(String setId) =>
      (db.update(db.workoutSets)..where((s) => s.id.equals(setId))).write(
        const WorkoutSetsCompanion(completedAt: Value(null)),
      );

  /// Ends the workout. Sets that were never completed are dropped, along with
  /// any exercise left without sets.
  Future<void> finish(String workoutId, {DateTime? now}) {
    return db.transaction(() async {
      final workout = await (db.select(
        db.workouts,
      )..where((w) => w.id.equals(workoutId))).getSingle();
      final links = await (db.select(
        db.workoutExercises,
      )..where((e) => e.workoutId.equals(workoutId))).get();

      DateTime? lastCompleted;
      for (final link in links) {
        final sets = await (db.select(
          db.workoutSets,
        )..where((s) => s.workoutExerciseId.equals(link.id))).get();
        final done = sets.where((s) => s.completedAt != null);
        for (final set in done) {
          if (lastCompleted == null ||
              set.completedAt!.isAfter(lastCompleted)) {
            lastCompleted = set.completedAt;
          }
        }
        if (done.isEmpty) {
          await (db.delete(
            db.workoutExercises,
          )..where((e) => e.id.equals(link.id))).go();
        } else {
          await (db.delete(db.workoutSets)..where(
                (s) =>
                    s.workoutExerciseId.equals(link.id) &
                    s.completedAt.isNull(),
              ))
              .go();
        }
      }

      final finishedAt = resolveFinishTime(
        startedAt: workout.startedAt,
        lastCompletedAt: lastCompleted,
        now: now ?? DateTime.now(),
      );
      await (db.update(db.workouts)..where((w) => w.id.equals(workoutId)))
          .write(WorkoutsCompanion(finishedAt: Value(finishedAt.toUtc())));
    });
  }

  /// Removes a workout and all its sets. Used for discarding an open workout
  /// and deleting a past one.
  Future<void> delete(String workoutId) =>
      (db.delete(db.workouts)..where((w) => w.id.equals(workoutId))).go();

  Future<void> rename(String workoutId, String name) =>
      (db.update(db.workouts)..where((w) => w.id.equals(workoutId))).write(
        WorkoutsCompanion(nameSnapshot: Value(name)),
      );

  Future<void> updateTimes(
    String workoutId, {
    required DateTime startedAt,
    required DateTime finishedAt,
  }) => (db.update(db.workouts)..where((w) => w.id.equals(workoutId))).write(
    WorkoutsCompanion(
      startedAt: Value(startedAt.toUtc()),
      finishedAt: Value(finishedAt.toUtc()),
    ),
  );
}
