import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakwat/data/backup.dart';
import 'package:hakwat/data/database.dart';
import 'package:hakwat/data/library_repositories.dart';
import 'package:hakwat/data/seed_exercises.dart';
import 'package:hakwat/data/workout_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final mockSource = File('assets/dev/mock_data.json').readAsStringSync();
  final fixedTime = DateTime.utc(2026, 11, 1);

  late AppDatabase db;

  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<Map<String, dynamic>> snapshot(AppDatabase source) async =>
      _normalized(await buildExport(source, now: fixedTime));

  test('the mock file passes the same checks as a real export', () {
    expect(() => parseBackup(mockSource), returnsNormally);
  });

  test('exporting, wiping and restoring gives identical data', () async {
    await replaceAllData(db, parseBackup(mockSource));

    // Exercise everything the mock file doesn't cover.
    final exercises = ExerciseRepository(db);
    final custom = await exercises.create('Zottman Curl', 'Biceps');
    await exercises.archive(custom, now: DateTime.utc(2026, 10, 31, 12));
    await SettingsRepository(db).set(AppSettings.unitKey, 'lb');

    final before = await snapshot(db);
    final json = await buildExportJson(db, now: fixedTime);

    await db.resetToFreshInstall();
    expect(await snapshot(db), isNot(before));

    await replaceAllData(db, parseBackup(json));
    expect(await snapshot(db), before);

    // A second file from the restored data matches byte for byte.
    expect(await buildExportJson(db, now: fixedTime), json);
  });

  test('export includes the open workout and archived exercises', () async {
    await replaceAllData(db, parseBackup(mockSource));
    await ExerciseRepository(db).archive(exerciseIdFor('Squat'));
    final parsed = parseBackup(await buildExportJson(db));
    expect(parsed.workouts.where((w) => w.finishedAt == null), hasLength(1));
    expect(parsed.exercises.where((e) => e.archivedAt != null), hasLength(1));
  });

  test('a restored open workout can be resumed and finished', () async {
    await replaceAllData(db, parseBackup(mockSource));
    final repo = WorkoutRepository(db);
    final open = await repo.watchOpen().first;
    expect(open!.nameSnapshot, 'Tonys Upper Minimalist');
    await repo.finish(open.id, now: DateTime.utc(2026, 11, 1));
    expect(await repo.watchOpen().first, isNull);
  });

  group('a bad file leaves existing data untouched', () {
    Map<String, dynamic> base() =>
        jsonDecode(mockSource) as Map<String, dynamic>;
    Map<String, dynamic> firstWorkout(Map<String, dynamic> root) =>
        (root['workouts'] as List).first as Map<String, dynamic>;

    final cases = <String, String Function()>{
      'not JSON': () => '{oops',
      'not an object': () => '[]',
      'another app': () => jsonEncode(base()..['app'] = 'other'),
      'no version': () => jsonEncode(base()..remove('schemaVersion')),
      'a newer version': () => jsonEncode(
        base()..['schemaVersion'] = currentSchemaVersion + 1,
      ),
      'a missing section': () => jsonEncode(base()..remove('routines')),
      'a wrong type': () => jsonEncode(base()..['workouts'] = 'nope'),
      'an unknown exercise': () {
        final root = base();
        final exercises = firstWorkout(root)['exercises'] as List;
        (exercises.first as Map)['exerciseId'] = 'missing';
        return jsonEncode(root);
      },
      'an unknown routine': () {
        final root = base();
        firstWorkout(root)['routineId'] = 'missing';
        return jsonEncode(root);
      },
      'a bad date': () {
        final root = base();
        firstWorkout(root)['startedAt'] = 'yesterday';
        return jsonEncode(root);
      },
      'duplicate IDs': () {
        final root = base();
        final list = root['exercises'] as List;
        (list[1] as Map)['id'] = (list[0] as Map)['id'];
        return jsonEncode(root);
      },
      'two open workouts': () {
        final root = base();
        for (final workout in (root['workouts'] as List).take(2)) {
          (workout as Map)['finishedAt'] = null;
        }
        return jsonEncode(root);
      },
    };

    for (final entry in cases.entries) {
      test(entry.key, () async {
        await replaceAllData(db, parseBackup(mockSource));
        final before = await snapshot(db);
        expect(
          () => parseBackup(entry.value()),
          throwsA(isA<BackupFormatException>()),
        );
        expect(await snapshot(db), before);
      });
    }
  });

  test('a failed write rolls the whole restore back', () async {
    await replaceAllData(db, parseBackup(mockSource));
    final before = await snapshot(db);

    // Passes parsing, but the two entries collide on the unique day column
    // only if the check were skipped, so build the failure directly.
    final good = parseBackup(mockSource);
    final bad = ParsedBackup(
      exercises: good.exercises,
      routines: good.routines,
      routineExercises: good.routineExercises,
      workouts: good.workouts,
      workoutExercises: good.workoutExercises,
      sets: good.sets,
      bodyweight: [good.bodyweight.first, good.bodyweight.first],
      settings: good.settings,
      exportedAt: null,
    );
    await expectLater(replaceAllData(db, bad), throwsA(anything));
    expect(await snapshot(db), before);
  });
}

/// Row order isn't part of the data, so sort every list by ID before comparing.
Map<String, dynamic> _normalized(Map<String, dynamic> export) {
  Object? sort(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final e in value.entries) e.key as String: sort(e.value),
      };
    }
    if (value is List) {
      final items = value.map(sort).toList();
      items.sort(
        (a, b) => ((a as Map)['id'] as String).compareTo(
          (b as Map)['id'] as String,
        ),
      );
      return items;
    }
    return value;
  }

  return sort(export) as Map<String, dynamic>;
}
