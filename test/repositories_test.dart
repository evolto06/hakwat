import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakwat/data/database.dart';
import 'package:hakwat/data/library_repositories.dart';
import 'package:hakwat/data/seed_exercises.dart';
import 'package:hakwat/data/workout_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late WorkoutRepository workouts;
  late RoutineRepository routines;
  late ExerciseRepository exercises;

  final bench = exerciseIdFor('Bench Press');
  final squat = exerciseIdFor('Squat');
  final curl = exerciseIdFor('Barbell Curl');

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    workouts = WorkoutRepository(db);
    routines = RoutineRepository(db);
    exercises = ExerciseRepository(db);
  });
  tearDown(() => db.close());

  Future<String> firstSetId(String workoutId) async {
    final detail = await workouts.watchDetail(workoutId).first;
    return detail!.exercises.first.sets.first.id;
  }

  Future<String> routine(List<RoutineItem> items, [String name = 'Push']) =>
      routines.create(name, items);

  group('library', () {
    test('a fresh install has the seeded library and no routines', () async {
      final all = await exercises.watchAll().first;
      final seeded = seedExerciseNames.values.expand((names) => names);
      expect(all.length, seeded.length);
      expect(all.every((e) => !e.isCustom), isTrue);
      expect(await routines.watchAll().first, isEmpty);
    });

    test('duplicate names are rejected regardless of case', () async {
      expect(
        () => exercises.create('bench press', 'Chest'),
        throwsA(isA<DuplicateExerciseName>()),
      );
    });

    test('an exercise with history can be archived and restored', () async {
      await exercises.archive(bench);
      var row = (await exercises.watchAll().first).firstWhere(
        (e) => e.id == bench,
      );
      expect(row.archivedAt, isNotNull);
      await exercises.unarchive(bench);
      row = (await exercises.watchAll().first).firstWhere((e) => e.id == bench);
      expect(row.archivedAt, isNull);
    });
  });

  group('routines', () {
    test('create, edit, duplicate and delete', () async {
      final a = await routine([
        RoutineItem(exerciseId: bench, targetSets: 3),
        RoutineItem(exerciseId: curl, targetSets: 2),
      ], 'A');
      final b = await routine(const [], 'B');

      await routines.save(a, 'A2', [
        RoutineItem(exerciseId: curl, targetSets: 4),
        RoutineItem(exerciseId: bench, targetSets: 1),
      ]);
      final edited = await routines.watchDetail(a).first;
      expect(edited!.routine.name, 'A2');
      expect(edited.exercises.map((e) => e.exercise.id), [curl, bench]);
      expect(edited.exercises.map((e) => e.row.targetSets), [4, 1]);

      final copy = await routines.duplicate(a);
      expect((await routines.watchAll().first).map((r) => r.id), [a, copy, b]);
      final copied = await routines.watchDetail(copy).first;
      expect(copied!.routine.name, 'A2 (copy)');
      expect(copied.exercises.map((e) => e.row.targetSets), [4, 1]);

      await routines.delete(a);
      expect((await routines.watchAll().first).map((r) => r.id), [copy, b]);
      expect(await routines.watchDetail(a).first, isNull);
    });
  });

  group('workouts', () {
    test('starting from a routine copies exercises and target sets', () async {
      final id = await routine([
        RoutineItem(exerciseId: bench, targetSets: 3),
        RoutineItem(exerciseId: curl, targetSets: 1),
      ]);
      final workoutId = await workouts.startFromRoutine(id);
      final detail = await workouts.watchDetail(workoutId).first;
      expect(detail!.workout.nameSnapshot, 'Push');
      expect(detail.exercises.map((e) => e.exercise.id), [bench, curl]);
      expect(detail.exercises.map((e) => e.sets.length), [3, 1]);
    });

    test('only one workout can be open', () async {
      final open = await workouts.startEmpty();
      await expectLater(
        workouts.startEmpty(),
        throwsA(
          isA<WorkoutAlreadyOpen>().having(
            (e) => e.workoutId,
            'workoutId',
            open,
          ),
        ),
      );
    });

    test('editing or deleting a routine never changes past workouts', () async {
      final id = await routine([RoutineItem(exerciseId: bench, targetSets: 1)]);
      final workoutId = await workouts.startFromRoutine(id);
      await workouts.completeSet(
        await firstSetId(workoutId),
        weightKg: 60,
        reps: 8,
        at: DateTime.now(),
      );
      await workouts.finish(workoutId);

      await routines.save(id, 'Renamed', [
        RoutineItem(exerciseId: squat, targetSets: 5),
      ]);
      var detail = await workouts.watchDetail(workoutId).first;
      expect(detail!.workout.nameSnapshot, 'Push');
      expect(detail.exercises.single.exercise.id, bench);

      await routines.delete(id);
      detail = await workouts.watchDetail(workoutId).first;
      expect(detail!.workout.routineId, isNull);
      expect(detail.workout.nameSnapshot, 'Push');
      expect(detail.exercises.single.sets.single.reps, 8);
    });

    test('values are saved as they change', () async {
      final workoutId = await workouts.startEmpty();
      await workouts.addExercises(workoutId, [bench]);
      final setId = await firstSetId(workoutId);
      await workouts.updateSetWeight(setId, 42.5);
      await workouts.updateSetReps(setId, 7);
      final set = (await workouts.watchDetail(
        workoutId,
      ).first)!.exercises.single.sets.single;
      expect(set.weightKg, 42.5);
      expect(set.reps, 7);
      expect(set.completedAt, isNull);
    });

    test('a new set carries over the last set', () async {
      final workoutId = await workouts.startEmpty();
      await workouts.addExercises(workoutId, [bench]);
      final detail = await workouts.watchDetail(workoutId).first;
      final setId = detail!.exercises.single.sets.single.id;
      await workouts.updateSetWeight(setId, 50);
      await workouts.updateSetReps(setId, 5);
      await workouts.addSet(detail.exercises.single.row.id);
      final sets = (await workouts.watchDetail(
        workoutId,
      ).first)!.exercises.single.sets;
      expect(sets.map((s) => s.sortOrder), [0, 1]);
      expect(sets.last.weightKg, 50);
      expect(sets.last.reps, 5);
      expect(sets.last.completedAt, isNull);
    });

    test('finishing removes incomplete sets and empty exercises', () async {
      final id = await routine([
        RoutineItem(exerciseId: bench, targetSets: 2),
        RoutineItem(exerciseId: curl, targetSets: 1),
      ]);
      final workoutId = await workouts.startFromRoutine(id);
      await workouts.completeSet(
        await firstSetId(workoutId),
        weightKg: 60,
        reps: 8,
        at: DateTime.now(),
      );
      await workouts.finish(workoutId);
      final detail = await workouts.watchDetail(workoutId).first;
      expect(detail!.exercises.single.exercise.id, bench);
      expect(detail.exercises.single.sets, hasLength(1));
    });

    test('a stale workout ends at its last completed set', () async {
      final start = DateTime.utc(2026, 10, 1, 10);
      final workoutId = await workouts.startEmpty(now: start);
      await workouts.addExercises(workoutId, [bench]);
      final lastSet = start.add(const Duration(minutes: 40));
      await workouts.completeSet(
        await firstSetId(workoutId),
        weightKg: 60,
        reps: 8,
        at: lastSet,
      );
      await workouts.finish(
        workoutId,
        now: start.add(const Duration(hours: 9)),
      );
      final detail = await workouts.watchDetail(workoutId).first;
      expect(detail!.workout.finishedAt, lastSet);
    });

    test('resolveFinishTime keeps now for an active workout', () {
      final start = DateTime.utc(2026, 10, 1, 10);
      final last = start.add(const Duration(hours: 1));
      final now = last.add(const Duration(minutes: 20));
      expect(
        resolveFinishTime(startedAt: start, lastCompletedAt: last, now: now),
        now,
      );
      final late = last.add(const Duration(hours: 4));
      expect(
        resolveFinishTime(startedAt: start, lastCompletedAt: last, now: late),
        last,
      );
      expect(
        resolveFinishTime(startedAt: start, lastCompletedAt: null, now: late),
        start,
      );
    });

    test('previous sets come from the latest earlier finished workout', () async {
      Future<void> session(DateTime start, double weight, {bool finish = true}) async {
        final id = await workouts.startEmpty(now: start);
        await workouts.addExercises(id, [bench]);
        await workouts.completeSet(
          await firstSetId(id),
          weightKg: weight,
          reps: 8,
          at: start.add(const Duration(minutes: 5)),
        );
        if (finish) {
          await workouts.finish(id, now: start.add(const Duration(minutes: 30)));
        }
      }

      await session(DateTime.utc(2026, 9, 1, 10), 50);
      await session(DateTime.utc(2026, 9, 8, 10), 55);
      await session(DateTime.utc(2026, 9, 15, 10), 60);
      await session(DateTime.utc(2026, 9, 22, 10), 99, finish: false);

      final atEnd = await workouts.previousSets(
        bench,
        before: DateTime.utc(2026, 9, 23),
      );
      expect(atEnd.single.weightKg, 60, reason: 'open workouts are skipped');

      final mid = await workouts.previousSets(
        bench,
        before: DateTime.utc(2026, 9, 15, 10),
      );
      expect(mid.single.weightKg, 55);

      expect(
        await workouts.previousSets(squat, before: DateTime.utc(2027)),
        isEmpty,
      );
    });

    test('log counts completed sets and keeps exercise order', () async {
      final id = await routine([
        RoutineItem(exerciseId: bench, targetSets: 2),
        RoutineItem(exerciseId: curl, targetSets: 1),
        RoutineItem(exerciseId: squat, targetSets: 1),
      ]);
      final workoutId = await workouts.startFromRoutine(id);
      final detail = await workouts.watchDetail(workoutId).first;
      for (final set in [
        ...detail!.exercises[0].sets,
        ...detail.exercises[1].sets,
      ]) {
        await workouts.completeSet(
          set.id,
          weightKg: 10,
          reps: 5,
          at: DateTime.now(),
        );
      }
      final summary = (await workouts.watchLog().first).single;
      expect(summary.isOpen, isTrue);
      expect(summary.duration, isNull);
      expect(summary.lines.map((l) => (l.exerciseName, l.completedSets)), [
        ('Bench Press', 2),
        ('Barbell Curl', 1),
      ]);
    });

    test('deleting a workout removes its sets', () async {
      final workoutId = await workouts.startEmpty();
      await workouts.addExercises(workoutId, [bench]);
      await workouts.delete(workoutId);
      expect(await db.select(db.workoutSets).get(), isEmpty);
      expect(await db.select(db.workoutExercises).get(), isEmpty);
      expect(await workouts.watchOpen().first, isNull);
    });
  });

  group('bodyweight', () {
    test('saving to a used day replaces its value', () async {
      final repo = BodyweightRepository(db);
      await repo.save(DateTime(2026, 10, 1), 80);
      await repo.save(DateTime(2026, 10, 1), 79.5);
      await repo.save(DateTime(2026, 10, 2), 79);
      final entries = await repo.watchAll().first;
      expect(entries.map((e) => (e.date, e.weightKg)), [
        ('2026-10-02', 79),
        ('2026-10-01', 79.5),
      ]);
    });
  });

  group('settings', () {
    test('defaults apply until a value is saved', () async {
      final repo = SettingsRepository(db);
      var settings = await repo.watch().first;
      expect(settings.restSeconds, 90);
      expect(settings.keepAwake, isTrue);
      await repo.set(AppSettings.restSecondsKey, '120');
      await repo.set(AppSettings.keepAwakeKey, 'false');
      settings = await repo.watch().first;
      expect(settings.restSeconds, 120);
      expect(settings.keepAwake, isFalse);
    });
  });
}
