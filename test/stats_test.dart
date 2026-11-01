import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakwat/core/format.dart';
import 'package:hakwat/data/backup.dart';
import 'package:hakwat/data/database.dart';
import 'package:hakwat/data/library_repositories.dart';
import 'package:hakwat/data/stats.dart';
import 'package:hakwat/data/workout_repository.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final source = File('assets/dev/mock_data.json').readAsStringSync();
  final raw = jsonDecode(source) as Map<String, dynamic>;

  late AppDatabase db;
  late StatsData data;

  Future<StatsData> load() async {
    final stats = StatsRepository(db);
    return StatsData(
      workouts: await stats.watchWorkouts().first,
      sets: await stats.watchSets().first,
      bodyweight: await BodyweightRepository(db).watchAll().first,
    );
  }

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    await replaceAllData(db, parseBackup(source));
    data = await load();
  });
  tearDown(() => db.close());

  group('totals match values worked out separately from the mock file', () {
    // These read the JSON directly and share no code with the app.
    final workouts = (raw['workouts'] as List).cast<Map<String, dynamic>>();
    final finished = workouts.where((w) => w['finishedAt'] != null).toList();
    final exerciseCategory = {
      for (final e in (raw['exercises'] as List).cast<Map<String, dynamic>>())
        e['id']: e['category'],
    };

    Iterable<(String, Map<String, dynamic>)> completedSets() sync* {
      for (final workout in finished) {
        for (final exercise
            in (workout['exercises'] as List).cast<Map<String, dynamic>>()) {
          for (final set
              in (exercise['sets'] as List).cast<Map<String, dynamic>>()) {
            if (set['completedAt'] != null) {
              yield (exerciseCategory[exercise['exerciseId']] as String, set);
            }
          }
        }
      }
    }

    final expectedSets = completedSets().length;
    final expectedReps = completedSets().fold<int>(
      0,
      (sum, s) => sum + (s.$2['reps'] as int),
    );
    final expectedVolume = completedSets().fold<double>(
      0,
      (sum, s) =>
          sum + (s.$2['weightKg'] as num).toDouble() * (s.$2['reps'] as int),
    );
    final expectedMinutes = finished.fold<int>(0, (sum, w) {
      final start = DateTime.parse(w['startedAt'] as String);
      final end = DateTime.parse(w['finishedAt'] as String);
      return sum + end.difference(start).inMinutes;
    });

    test('the mock data has something to count', () {
      expect(workouts, hasLength(25));
      expect(finished, hasLength(24));
      expect(expectedSets, greaterThan(100));
    });

    test('number of workouts leaves out the open one', () {
      expect(StatsCalculator(data, WeightUnit.kg).totalWorkouts, 24);
    });

    test('duration', () {
      expect(
        StatsCalculator(data, WeightUnit.kg).totalDuration.inMinutes,
        expectedMinutes,
      );
    });

    test('volume', () {
      expect(
        StatsCalculator(data, WeightUnit.kg).totalVolumeKg,
        closeTo(expectedVolume, 0.001),
      );
    });

    test('sets, reps and reps per set', () {
      final calculator = StatsCalculator(data, WeightUnit.kg);
      expect(calculator.totalSets, expectedSets);
      expect(calculator.totalReps, expectedReps);
      expect(calculator.repsPerSet, closeTo(expectedReps / expectedSets, 1e-9));
    });

    test('categories add up to the overall totals', () {
      final calculator = StatsCalculator(data, WeightUnit.kg);
      for (final category in exerciseCategory.values.toSet()) {
        final sets = completedSets().where((s) => s.$1 == category);
        final stats = calculator.category(category);
        expect(stats.setCount, sets.length, reason: category);
        expect(
          stats.volumeKg,
          closeTo(
            sets.fold<double>(
              0,
              (sum, s) =>
                  sum +
                  (s.$2['weightKg'] as num).toDouble() * (s.$2['reps'] as int),
            ),
            0.001,
          ),
          reason: category,
        );
      }
    });

    test('monthly bars add up to the totals', () {
      final calculator = StatsCalculator(data, WeightUnit.kg);
      final now = DateTime(2026, 11, 1);
      double sum(OverallStat stat) => calculator
          .series(stat, StatPeriod.month, now)
          .fold(0, (total, p) => total + (p.value ?? 0));
      expect(sum(OverallStat.workouts), 24);
      expect(sum(OverallStat.sets), expectedSets);
      expect(sum(OverallStat.reps), expectedReps);
      expect(sum(OverallStat.volume), closeTo(expectedVolume, 0.001));
    });
  });

  test('finishing the open workout brings it into the stats', () async {
    final before = StatsCalculator(data, WeightUnit.kg);
    final repo = WorkoutRepository(db);
    final open = await repo.watchOpen().first;
    await repo.finish(open!.id, now: DateTime.utc(2026, 10, 30, 11));
    final after = StatsCalculator(await load(), WeightUnit.kg);
    expect(after.totalWorkouts, before.totalWorkouts + 1);
    expect(after.totalSets, greaterThan(before.totalSets));
  });

  test('bodyweight entries reach the chart, converted to the unit', () async {
    await BodyweightRepository(db).save(DateTime(2026, 11, 2), 100);
    final fresh = await load();
    final now = DateTime(2026, 11, 3);
    final kg = StatsCalculator(
      fresh,
      WeightUnit.kg,
    ).series(OverallStat.bodyweight, StatPeriod.month, now);
    final lb = StatsCalculator(
      fresh,
      WeightUnit.lb,
    ).series(OverallStat.bodyweight, StatPeriod.month, now);
    expect(kg.last.label, 'Nov');
    expect(kg.last.value, 100);
    expect(lb.last.value, closeTo(220.46, 0.01));
    expect(kg.first.value, isNull, reason: 'no entries that month');
  });

  test('best set takes the heaviest weight, then the most reps', () {
    SetFact fact(String name, double weight, int reps) => SetFact(
      startedAt: DateTime.utc(2026),
      exerciseName: name,
      category: 'Chest',
      weightKg: weight,
      reps: reps,
    );
    final best = CategoryStats([
      fact('B', 50, 10),
      fact('B', 60, 3),
      fact('B', 60, 5),
      fact('A', 0, 12),
      fact('A', 0, 20),
    ]).bestSets;
    expect(best.map((b) => (b.exerciseName, b.weightKg, b.reps)), [
      ('A', 0, 20),
      ('B', 60, 5),
    ]);
  });

  test('bodyweight exercises count as zero volume', () {
    final set = SetFact(
      startedAt: DateTime.utc(2026),
      exerciseName: 'Push-Up',
      category: 'Chest',
      weightKg: 0,
      reps: 30,
    );
    expect(StatsCalculator.volumeOf([set]), 0);
    expect(StatsCalculator.repsOf([set]), 30);
  });

  test('empty data gives zeros, not errors', () {
    final calculator = StatsCalculator(const StatsData(), WeightUnit.kg);
    expect(calculator.repsPerSet, 0);
    for (final stat in OverallStat.values) {
      expect(calculator.tiles(stat), isNotEmpty);
      expect(
        calculator.series(stat, StatPeriod.year, DateTime(2026)),
        hasLength(StatPeriod.year.bucketCount),
      );
    }
  });

  group('buckets', () {
    test('weeks run Monday to Monday and end with the current week', () {
      final buckets = bucketsFor(StatPeriod.week, DateTime(2026, 11, 1));
      expect(buckets, hasLength(12));
      expect(buckets.last.start, DateTime(2026, 10, 26));
      expect(buckets.last.end, DateTime(2026, 11, 2));
      expect(buckets.first.start.weekday, DateTime.monday);
    });

    test('months cross the year boundary', () {
      final buckets = bucketsFor(StatPeriod.month, DateTime(2026, 2, 10));
      expect(buckets.first.start, DateTime(2025, 3));
      expect(buckets.last.start, DateTime(2026, 2));
    });

    test('years end with the current year', () {
      final buckets = bucketsFor(StatPeriod.year, DateTime(2026, 6));
      expect(buckets.map((b) => b.label), [
        '2022',
        '2023',
        '2024',
        '2025',
        '2026',
      ]);
    });
  });

  group('format', () {
    test('kg and lb round trip', () {
      expect(formatWeight(WeightUnit.lb.toKg(135), WeightUnit.lb), '135');
      expect(formatWeight(62.5, WeightUnit.kg), '62.5');
      expect(formatWeight(60, WeightUnit.kg), '60');
    });

    test('time range adds the date only when it crosses midnight', () {
      final start = DateTime(2026, 10, 30, 18);
      // intl puts a narrow no-break space before AM and PM.
      String range(DateTime end) =>
          formatTimeRange(start, end).replaceAll(' ', ' ');
      expect(range(DateTime(2026, 10, 30, 19, 47)), '6:00 PM to 7:47 PM');
      expect(range(DateTime(2026, 11, 1, 22)), '6:00 PM to Nov 1, 10:00 PM');
    });

    test('durations', () {
      expect(formatDuration(const Duration(minutes: 107)), '107 min');
      expect(formatDuration(const Duration(minutes: 200)), '3 h 20 min');
      expect(formatClock(const Duration(seconds: 65)), '1:05');
      expect(formatClock(const Duration(hours: 1, seconds: 5)), '1:00:05');
      expect(formatClock(const Duration(seconds: -5)), '0:00');
    });
  });
}
