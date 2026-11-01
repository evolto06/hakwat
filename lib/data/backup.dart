import 'dart:convert';

import 'database.dart';

/// The format every export writes.
const currentSchemaVersion = 1;

const _appId = 'hakwat';

/// A file that can't be restored. [message] is written for the user.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;

  @override
  String toString() => message;
}

String _time(DateTime value) => value.toUtc().toIso8601String();

/// Reads all data into the export format.
Future<Map<String, dynamic>> buildExport(
  AppDatabase db, {
  DateTime? now,
}) async {
  final exercises = await db.select(db.exercises).get();
  final routines = await db.select(db.routines).get();
  final routineExercises = await db.select(db.routineExercises).get();
  final workouts = await db.select(db.workouts).get();
  final workoutExercises = await db.select(db.workoutExercises).get();
  final sets = await db.select(db.workoutSets).get();
  final bodyweight = await db.select(db.bodyweightEntries).get();
  final settings = await db.select(db.settings).get();

  final itemsByRoutine = <String, List<RoutineExercise>>{};
  for (final item in routineExercises) {
    itemsByRoutine.putIfAbsent(item.routineId, () => []).add(item);
  }
  final exercisesByWorkout = <String, List<WorkoutExercise>>{};
  for (final item in workoutExercises) {
    exercisesByWorkout.putIfAbsent(item.workoutId, () => []).add(item);
  }
  final setsByExercise = <String, List<WorkoutSet>>{};
  for (final set in sets) {
    setsByExercise.putIfAbsent(set.workoutExerciseId, () => []).add(set);
  }

  return {
    'app': _appId,
    'schemaVersion': currentSchemaVersion,
    'exportedAt': _time(now ?? DateTime.now()),
    'exercises': [
      for (final e in exercises)
        {
          'id': e.id,
          'name': e.name,
          'category': e.category,
          'isCustom': e.isCustom,
          'archivedAt': e.archivedAt == null ? null : _time(e.archivedAt!),
        },
    ],
    'routines': [
      for (final r in routines)
        {
          'id': r.id,
          'name': r.name,
          'sortOrder': r.sortOrder,
          'exercises': [
            for (final item in itemsByRoutine[r.id] ?? const <RoutineExercise>[])
              {
                'id': item.id,
                'exerciseId': item.exerciseId,
                'sortOrder': item.sortOrder,
                'targetSets': item.targetSets,
              },
          ],
        },
    ],
    'workouts': [
      for (final w in workouts)
        {
          'id': w.id,
          'routineId': w.routineId,
          'name': w.nameSnapshot,
          'startedAt': _time(w.startedAt),
          'finishedAt': w.finishedAt == null ? null : _time(w.finishedAt!),
          'exercises': [
            for (final item
                in exercisesByWorkout[w.id] ?? const <WorkoutExercise>[])
              {
                'id': item.id,
                'exerciseId': item.exerciseId,
                'sortOrder': item.sortOrder,
                'sets': [
                  for (final s in setsByExercise[item.id] ?? const <WorkoutSet>[])
                    {
                      'id': s.id,
                      'sortOrder': s.sortOrder,
                      'weightKg': s.weightKg,
                      'reps': s.reps,
                      'completedAt': s.completedAt == null
                          ? null
                          : _time(s.completedAt!),
                    },
                ],
              },
          ],
        },
    ],
    'bodyweight': [
      for (final b in bodyweight)
        {'id': b.id, 'date': b.date, 'weightKg': b.weightKg},
    ],
    'settings': {for (final s in settings) s.key: s.value},
  };
}

Future<String> buildExportJson(AppDatabase db, {DateTime? now}) async =>
    const JsonEncoder.withIndent(
      ' ',
    ).convert(await buildExport(db, now: now));

/// A fully checked export, ready to write. Nothing touches the database until
/// parsing has succeeded, so a bad file leaves existing data alone.
class ParsedBackup {
  ParsedBackup({
    required this.exercises,
    required this.routines,
    required this.routineExercises,
    required this.workouts,
    required this.workoutExercises,
    required this.sets,
    required this.bodyweight,
    required this.settings,
    required this.exportedAt,
  });

  final List<Exercise> exercises;
  final List<Routine> routines;
  final List<RoutineExercise> routineExercises;
  final List<Workout> workouts;
  final List<WorkoutExercise> workoutExercises;
  final List<WorkoutSet> sets;
  final List<BodyweightEntry> bodyweight;
  final List<SettingRow> settings;
  final DateTime? exportedAt;
}

Never _bad(String message) => throw BackupFormatException(message);

T _field<T>(Map<String, dynamic> map, String key, String where) {
  final value = map[key];
  if (value is T) return value;
  _bad('$where has a missing or invalid "$key".');
}

DateTime _timeField(Map<String, dynamic> map, String key, String where) {
  final parsed = DateTime.tryParse(_field<String>(map, key, where));
  if (parsed == null) _bad('$where has an invalid date in "$key".');
  return parsed.toUtc();
}

DateTime? _optionalTime(Map<String, dynamic> map, String key, String where) =>
    map[key] == null ? null : _timeField(map, key, where);

double? _optionalDouble(Map<String, dynamic> map, String key, String where) =>
    map[key] == null ? null : _field<num>(map, key, where).toDouble();

List<Map<String, dynamic>> _list(
  Map<String, dynamic> map,
  String key,
  String where,
) {
  final value = _field<List<dynamic>>(map, key, where);
  return [
    for (final item in value)
      if (item is Map<String, dynamic>)
        item
      else
        _bad('$where has an invalid entry in "$key".'),
  ];
}

/// Brings an older export up to [currentSchemaVersion]. Each format change adds
/// a step here, so newer app versions can still read old files.
Map<String, dynamic> _upgrade(Map<String, dynamic> root, int fromVersion) {
  return root;
}

/// Checks a file's contents completely and throws [BackupFormatException] if
/// anything is wrong.
ParsedBackup parseBackup(String source) {
  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on FormatException {
    _bad('This file is not valid JSON.');
  }
  if (decoded is! Map<String, dynamic> || decoded['app'] != _appId) {
    _bad('This is not a hakwat export file.');
  }
  final version = decoded['schemaVersion'];
  if (version is! int || version < 1) {
    _bad('This file has no valid schemaVersion.');
  }
  if (version > currentSchemaVersion) {
    _bad('This file comes from a newer version of hakwat. Update the app first.');
  }
  final root = _upgrade(decoded, version);

  final ids = <String>{};
  String uniqueId(Map<String, dynamic> map, String where) {
    final id = _field<String>(map, 'id', where);
    if (id.isEmpty || !ids.add(id)) _bad('$where has a duplicate or empty ID.');
    return id;
  }

  final exercises = <Exercise>[];
  for (final e in _list(root, 'exercises', 'The file')) {
    const where = 'An exercise';
    exercises.add(
      Exercise(
        id: uniqueId(e, where),
        name: _field<String>(e, 'name', where),
        category: _field<String>(e, 'category', where),
        isCustom: _field<bool>(e, 'isCustom', where),
        archivedAt: _optionalTime(e, 'archivedAt', where),
      ),
    );
  }
  final exerciseIds = {for (final e in exercises) e.id};
  String exerciseRef(Map<String, dynamic> map, String where) {
    final id = _field<String>(map, 'exerciseId', where);
    if (!exerciseIds.contains(id)) _bad('$where refers to an unknown exercise.');
    return id;
  }

  final routines = <Routine>[];
  final routineExercises = <RoutineExercise>[];
  for (final r in _list(root, 'routines', 'The file')) {
    const where = 'A routine';
    final id = uniqueId(r, where);
    routines.add(
      Routine(
        id: id,
        name: _field<String>(r, 'name', where),
        sortOrder: _field<int>(r, 'sortOrder', where),
      ),
    );
    for (final item in _list(r, 'exercises', where)) {
      const itemWhere = 'A routine exercise';
      routineExercises.add(
        RoutineExercise(
          id: uniqueId(item, itemWhere),
          routineId: id,
          exerciseId: exerciseRef(item, itemWhere),
          sortOrder: _field<int>(item, 'sortOrder', itemWhere),
          targetSets: _field<int>(item, 'targetSets', itemWhere),
        ),
      );
    }
  }
  final routineIds = {for (final r in routines) r.id};

  final workouts = <Workout>[];
  final workoutExercises = <WorkoutExercise>[];
  final sets = <WorkoutSet>[];
  for (final w in _list(root, 'workouts', 'The file')) {
    const where = 'A workout';
    final id = uniqueId(w, where);
    final routineId = w['routineId'];
    if (routineId != null &&
        (routineId is! String || !routineIds.contains(routineId))) {
      _bad('$where refers to an unknown routine.');
    }
    workouts.add(
      Workout(
        id: id,
        routineId: routineId as String?,
        nameSnapshot: _field<String>(w, 'name', where),
        startedAt: _timeField(w, 'startedAt', where),
        finishedAt: _optionalTime(w, 'finishedAt', where),
      ),
    );
    for (final item in _list(w, 'exercises', where)) {
      const itemWhere = 'A workout exercise';
      final itemId = uniqueId(item, itemWhere);
      workoutExercises.add(
        WorkoutExercise(
          id: itemId,
          workoutId: id,
          exerciseId: exerciseRef(item, itemWhere),
          sortOrder: _field<int>(item, 'sortOrder', itemWhere),
        ),
      );
      for (final s in _list(item, 'sets', itemWhere)) {
        const setWhere = 'A set';
        final reps = s['reps'];
        if (reps != null && reps is! int) _bad('$setWhere has invalid reps.');
        sets.add(
          WorkoutSet(
            id: uniqueId(s, setWhere),
            workoutExerciseId: itemId,
            sortOrder: _field<int>(s, 'sortOrder', setWhere),
            weightKg: _optionalDouble(s, 'weightKg', setWhere),
            reps: reps as int?,
            completedAt: _optionalTime(s, 'completedAt', setWhere),
          ),
        );
      }
    }
  }
  if (workouts.where((w) => w.finishedAt == null).length > 1) {
    _bad('This file has more than one open workout.');
  }

  final days = <String>{};
  final bodyweight = <BodyweightEntry>[];
  for (final b in _list(root, 'bodyweight', 'The file')) {
    const where = 'A bodyweight entry';
    final date = _field<String>(b, 'date', where);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(date) ||
        DateTime.tryParse(date) == null) {
      _bad('$where has an invalid date.');
    }
    if (!days.add(date)) _bad('This file has two bodyweight entries on $date.');
    bodyweight.add(
      BodyweightEntry(
        id: uniqueId(b, where),
        date: date,
        weightKg: _field<num>(b, 'weightKg', where).toDouble(),
      ),
    );
  }

  final settingsMap = _field<Map<String, dynamic>>(root, 'settings', 'The file');
  final settings = <SettingRow>[
    for (final entry in settingsMap.entries)
      if (entry.value is String)
        SettingRow(key: entry.key, value: entry.value as String)
      else
        _bad('The setting "${entry.key}" is invalid.'),
  ];

  return ParsedBackup(
    exercises: exercises,
    routines: routines,
    routineExercises: routineExercises,
    workouts: workouts,
    workoutExercises: workoutExercises,
    sets: sets,
    bodyweight: bodyweight,
    settings: settings,
    exportedAt: root['exportedAt'] is String
        ? DateTime.tryParse(root['exportedAt'] as String)
        : null,
  );
}

/// Replaces all data in one transaction. If any write fails, the database is
/// left as it was.
Future<void> replaceAllData(AppDatabase db, ParsedBackup data) {
  return db.transaction(() async {
    await db.deleteEverything();
    await db.batch((b) {
      b.insertAll(db.exercises, data.exercises);
      b.insertAll(db.routines, data.routines);
      b.insertAll(db.routineExercises, data.routineExercises);
      b.insertAll(db.workouts, data.workouts);
      b.insertAll(db.workoutExercises, data.workoutExercises);
      b.insertAll(db.workoutSets, data.sets);
      b.insertAll(db.bodyweightEntries, data.bodyweight);
      b.insertAll(db.settings, data.settings);
    });
  });
}
