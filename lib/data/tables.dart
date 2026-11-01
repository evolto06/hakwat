import 'package:drift/drift.dart';

/// Every table uses a UUID primary key and all timestamps are stored in UTC.

class Exercises extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get category => text()();
  BoolColumn get isCustom => boolean().withDefault(const Constant(false))();

  /// Archived rather than deleted, so history survives.
  DateTimeColumn get archivedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Routines extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'routine_exercises_routine', columns: {#routineId})
class RoutineExercises extends Table {
  TextColumn get id => text()();
  TextColumn get routineId =>
      text().references(Routines, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get sortOrder => integer()();
  IntColumn get targetSets => integer().withDefault(const Constant(3))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A workout copies its name and exercises when it starts, so editing or
/// deleting a routine never changes past workouts.
@TableIndex(name: 'workouts_started', columns: {#startedAt})
class Workouts extends Table {
  TextColumn get id => text()();
  TextColumn get routineId => text().nullable().references(
    Routines,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get nameSnapshot => text()();
  DateTimeColumn get startedAt => dateTime()();

  /// Empty means the workout is still open.
  DateTimeColumn get finishedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@TableIndex(name: 'workout_exercises_workout', columns: {#workoutId})
@TableIndex(name: 'workout_exercises_exercise', columns: {#exerciseId})
class WorkoutExercises extends Table {
  TextColumn get id => text()();
  TextColumn get workoutId =>
      text().references(Workouts, #id, onDelete: KeyAction.cascade)();
  TextColumn get exerciseId => text().references(Exercises, #id)();
  IntColumn get sortOrder => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('WorkoutSet')
@TableIndex(name: 'sets_workout_exercise', columns: {#workoutExerciseId})
class WorkoutSets extends Table {
  @override
  String get tableName => 'sets';

  TextColumn get id => text()();
  TextColumn get workoutExerciseId =>
      text().references(WorkoutExercises, #id, onDelete: KeyAction.cascade)();
  IntColumn get sortOrder => integer()();
  RealColumn get weightKg => real().nullable()();
  IntColumn get reps => integer().nullable()();

  /// Empty means the set was planned but not done yet.
  DateTimeColumn get completedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('BodyweightEntry')
class BodyweightEntries extends Table {
  TextColumn get id => text()();

  /// A calendar day (`yyyy-MM-dd`) rather than a timestamp, so an entry stays
  /// on the same day when the phone changes time zone.
  TextColumn get date => text().unique()();
  RealColumn get weightKg => real()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Kept in the database so exports include it.
@DataClassName('SettingRow')
class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}
