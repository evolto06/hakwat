import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'seed_exercises.dart';
import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Exercises,
    Routines,
    RoutineExercises,
    Workouts,
    WorkoutExercises,
    WorkoutSets,
    BodyweightEntries,
    Settings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
    : super(executor ?? driftDatabase(name: 'hakwat'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await seedLibrary();
    },
    // Feature-work policy: a structure change wipes the database, and the mock
    // data is loaded again. Real migrations are part of the release work.
    onUpgrade: (m, from, to) async {
      for (final entity in allSchemaEntities.toList().reversed) {
        await m.drop(entity);
      }
      await m.createAll();
      await seedLibrary();
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Future<void> seedLibrary() async {
    await batch((b) {
      b.insertAll(exercises, [
        for (final entry in seedExerciseNames.entries)
          for (final name in entry.value)
            ExercisesCompanion.insert(
              id: exerciseIdFor(name),
              name: name,
              category: entry.key,
            ),
      ]);
    });
  }

  /// Removes every row, children first. Call inside a transaction when it is
  /// part of a larger replacement.
  Future<void> deleteEverything() async {
    await transaction(() async {
      await delete(workoutSets).go();
      await delete(workoutExercises).go();
      await delete(workouts).go();
      await delete(routineExercises).go();
      await delete(routines).go();
      await delete(bodyweightEntries).go();
      await delete(settings).go();
      await delete(exercises).go();
    });
  }

  /// Puts the app back to how a fresh install looks.
  Future<void> resetToFreshInstall() async {
    await transaction(() async {
      await deleteEverything();
      await seedLibrary();
    });
  }
}
