import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../core/format.dart';
import 'database.dart';

const _uuid = Uuid();

class RoutineItem {
  const RoutineItem({required this.exerciseId, required this.targetSets});
  final String exerciseId;
  final int targetSets;
}

class RoutineExerciseDetail {
  const RoutineExerciseDetail(this.row, this.exercise);
  final RoutineExercise row;
  final Exercise exercise;
}

class RoutineDetail {
  const RoutineDetail(this.routine, this.exercises);
  final Routine routine;
  final List<RoutineExerciseDetail> exercises;
}

class RoutineRepository {
  RoutineRepository(this.db);
  final AppDatabase db;

  Stream<List<Routine>> watchAll() => (db.select(
    db.routines,
  )..orderBy([(r) => OrderingTerm.asc(r.sortOrder)])).watch();

  Stream<RoutineDetail?> watchDetail(String routineId) async* {
    final query =
        db.select(db.routines).join([
            leftOuterJoin(
              db.routineExercises,
              db.routineExercises.routineId.equalsExp(db.routines.id),
            ),
            leftOuterJoin(
              db.exercises,
              db.exercises.id.equalsExp(db.routineExercises.exerciseId),
            ),
          ])
          ..where(db.routines.id.equals(routineId))
          ..orderBy([OrderingTerm.asc(db.routineExercises.sortOrder)]);

    yield* query.watch().map((rows) {
      if (rows.isEmpty) return null;
      return RoutineDetail(rows.first.readTable(db.routines), [
        for (final row in rows)
          if (row.readTableOrNull(db.routineExercises) case final link?)
            RoutineExerciseDetail(link, row.readTable(db.exercises)),
      ]);
    });
  }

  /// Creates a routine at the end of the list and returns its ID.
  Future<String> create(String name, List<RoutineItem> items) {
    return db.transaction(() async {
      final id = _uuid.v4();
      await db
          .into(db.routines)
          .insert(
            RoutinesCompanion.insert(
              id: id,
              name: name,
              sortOrder: await _nextOrder(),
            ),
          );
      await _insertItems(id, items);
      return id;
    });
  }

  Future<void> save(String routineId, String name, List<RoutineItem> items) {
    return db.transaction(() async {
      await (db.update(db.routines)..where((r) => r.id.equals(routineId)))
          .write(RoutinesCompanion(name: Value(name)));
      await (db.delete(
        db.routineExercises,
      )..where((r) => r.routineId.equals(routineId))).go();
      await _insertItems(routineId, items);
    });
  }

  /// Copies a routine directly below the original and returns the copy's ID.
  Future<String> duplicate(String routineId) {
    return db.transaction(() async {
      final original = await (db.select(
        db.routines,
      )..where((r) => r.id.equals(routineId))).getSingle();
      final items =
          await (db.select(db.routineExercises)
                ..where((r) => r.routineId.equals(routineId))
                ..orderBy([(r) => OrderingTerm.asc(r.sortOrder)]))
              .get();

      await db.customUpdate(
        'UPDATE routines SET sort_order = sort_order + 1 WHERE sort_order > ?',
        variables: [Variable.withInt(original.sortOrder)],
        updates: {db.routines},
      );

      final id = _uuid.v4();
      await db
          .into(db.routines)
          .insert(
            RoutinesCompanion.insert(
              id: id,
              name: '${original.name} (copy)',
              sortOrder: original.sortOrder + 1,
            ),
          );
      await _insertItems(id, [
        for (final item in items)
          RoutineItem(exerciseId: item.exerciseId, targetSets: item.targetSets),
      ]);
      return id;
    });
  }

  /// Past workouts keep their copied name and exercises.
  Future<void> delete(String routineId) =>
      (db.delete(db.routines)..where((r) => r.id.equals(routineId))).go();

  Future<int> _nextOrder() async {
    final rows = await db.select(db.routines).get();
    return rows.fold<int>(
      0,
      (next, r) => r.sortOrder >= next ? r.sortOrder + 1 : next,
    );
  }

  Future<void> _insertItems(String routineId, List<RoutineItem> items) async {
    for (final (index, item) in items.indexed) {
      await db
          .into(db.routineExercises)
          .insert(
            RoutineExercisesCompanion.insert(
              id: _uuid.v4(),
              routineId: routineId,
              exerciseId: item.exerciseId,
              sortOrder: index,
              targetSets: Value(item.targetSets),
            ),
          );
    }
  }
}

class DuplicateExerciseName implements Exception {
  const DuplicateExerciseName(this.name);
  final String name;
}

class ExerciseRepository {
  ExerciseRepository(this.db);
  final AppDatabase db;

  Stream<List<Exercise>> watchAll() => (db.select(
    db.exercises,
  )..orderBy([(e) => OrderingTerm.asc(e.name)])).watch();

  Future<String> create(
    String name,
    String category, {
    bool isMachine = false,
    String? gymId,
    WeightMode? weightMode,
  }) {
    _checkEquipment(isMachine, gymId, weightMode);
    return db.transaction(() async {
      await _checkNameFree(name, gymId);
      final id = _uuid.v4();
      await db
          .into(db.exercises)
          .insert(
            ExercisesCompanion.insert(
              id: id,
              name: name,
              category: category,
              isCustom: const Value(true),
              isMachine: Value(isMachine),
              gymId: Value(gymId),
              weightMode: Value(weightMode),
            ),
          );
      return id;
    });
  }

  Future<void> edit(
    String id,
    String name,
    String category, {
    required bool isMachine,
    required String? gymId,
    required WeightMode? weightMode,
  }) {
    _checkEquipment(isMachine, gymId, weightMode);
    return db.transaction(() async {
      await _checkNameFree(name, gymId, except: id);
      await (db.update(db.exercises)..where((e) => e.id.equals(id))).write(
        ExercisesCompanion(
          name: Value(name),
          category: Value(category),
          isMachine: Value(isMachine),
          gymId: Value(gymId),
          weightMode: Value(weightMode),
        ),
      );
    });
  }

  Future<void> archive(String id, {DateTime? now}) =>
      (db.update(db.exercises)..where((e) => e.id.equals(id))).write(
        ExercisesCompanion(archivedAt: Value((now ?? DateTime.now()).toUtc())),
      );

  Future<void> unarchive(String id) =>
      (db.update(db.exercises)..where((e) => e.id.equals(id))).write(
        const ExercisesCompanion(archivedAt: Value(null)),
      );

  /// Free weights are universal, so gyms and pin numbers are for machines only.
  void _checkEquipment(bool isMachine, String? gymId, WeightMode? mode) {
    if (isMachine) return;
    if (gymId != null) throw ArgumentError('A free weight cannot have a gym.');
    if (mode == WeightMode.pin) {
      throw ArgumentError('A free weight cannot log a pin number.');
    }
  }

  /// Two gyms can each have their own Chest Fly, but one gym can't have two.
  Future<void> _checkNameFree(
    String name,
    String? gymId, {
    String? except,
  }) async {
    final wanted = name.trim().toLowerCase();
    final all = await db.select(db.exercises).get();
    final clash = all.any(
      (e) =>
          e.id != except &&
          e.gymId == gymId &&
          e.name.trim().toLowerCase() == wanted,
    );
    if (clash) throw DuplicateExerciseName(name);
  }
}

class DuplicateGymName implements Exception {
  const DuplicateGymName(this.name);
  final String name;
}

/// A gym can't be deleted while exercises belong to it, since they hold history.
class GymInUse implements Exception {
  const GymInUse(this.exerciseCount);
  final int exerciseCount;
}

class GymRepository {
  GymRepository(this.db);
  final AppDatabase db;

  Stream<List<Gym>> watchAll() =>
      (db.select(db.gyms)..orderBy([(g) => OrderingTerm.asc(g.name)])).watch();

  Future<String> create(String name) {
    return db.transaction(() async {
      await _checkNameFree(name);
      final id = _uuid.v4();
      await db.into(db.gyms).insert(GymsCompanion.insert(id: id, name: name));
      return id;
    });
  }

  Future<void> rename(String id, String name) {
    return db.transaction(() async {
      await _checkNameFree(name, except: id);
      await (db.update(
        db.gyms,
      )..where((g) => g.id.equals(id))).write(GymsCompanion(name: Value(name)));
    });
  }

  Future<void> delete(String id) {
    return db.transaction(() async {
      final owned = await (db.select(
        db.exercises,
      )..where((e) => e.gymId.equals(id))).get();
      if (owned.isNotEmpty) throw GymInUse(owned.length);
      await (db.delete(db.gyms)..where((g) => g.id.equals(id))).go();
    });
  }

  Future<void> _checkNameFree(String name, {String? except}) async {
    final wanted = name.trim().toLowerCase();
    final all = await db.select(db.gyms).get();
    final clash = all.any(
      (g) => g.id != except && g.name.trim().toLowerCase() == wanted,
    );
    if (clash) throw DuplicateGymName(name);
  }
}

class BodyweightRepository {
  BodyweightRepository(this.db);
  final AppDatabase db;

  /// Newest first.
  Stream<List<BodyweightEntry>> watchAll() => (db.select(
    db.bodyweightEntries,
  )..orderBy([(b) => OrderingTerm.desc(b.date)])).watch();

  /// Each day holds one entry, so saving to a used day replaces its value.
  Future<void> save(DateTime localDay, double weightKg) {
    return db
        .into(db.bodyweightEntries)
        .insert(
          BodyweightEntriesCompanion.insert(
            id: _uuid.v4(),
            date: formatDayKey(localDay),
            weightKg: weightKg,
          ),
          onConflict: DoUpdate(
            (_) => BodyweightEntriesCompanion(weightKg: Value(weightKg)),
            target: [db.bodyweightEntries.date],
          ),
        );
  }

  Future<void> delete(String id) =>
      (db.delete(db.bodyweightEntries)..where((b) => b.id.equals(id))).go();
}

class AppSettings {
  const AppSettings({
    this.unit = WeightUnit.kg,
    this.restSeconds = 90,
    this.keepAwake = true,
    this.restAlert = true,
    this.pinIncrementLb = defaultPinIncrementLb,
  });

  static const unitKey = 'unit';
  static const restSecondsKey = 'rest_seconds';
  static const keepAwakeKey = 'keep_awake';
  static const restAlertKey = 'rest_alert';
  static const pinIncrementKey = 'pin_increment_lb';

  factory AppSettings.fromRows(List<SettingRow> rows) {
    final map = {for (final row in rows) row.key: row.value};
    return AppSettings(
      unit: WeightUnit.parse(map[unitKey]),
      restSeconds: int.tryParse(map[restSecondsKey] ?? '') ?? 90,
      keepAwake: map[keepAwakeKey] != 'false',
      restAlert: map[restAlertKey] != 'false',
      pinIncrementLb: switch (int.tryParse(map[pinIncrementKey] ?? '')) {
        final int value when value > 0 => value,
        _ => defaultPinIncrementLb,
      },
    );
  }

  final WeightUnit unit;
  final int restSeconds;
  final bool keepAwake;
  final bool restAlert;
  final int pinIncrementLb;
}

class SettingsRepository {
  SettingsRepository(this.db);
  final AppDatabase db;

  Stream<AppSettings> watch() =>
      db.select(db.settings).watch().map(AppSettings.fromRows);

  Future<void> set(String key, String value) => db
      .into(db.settings)
      .insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));
}
