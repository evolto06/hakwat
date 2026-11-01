import 'package:drift/drift.dart';
import 'package:intl/intl.dart';

import '../core/format.dart';
import 'database.dart';

/// A finished workout.
class WorkoutFact {
  const WorkoutFact({required this.startedAt, required this.finishedAt});
  final DateTime startedAt;
  final DateTime finishedAt;

  Duration get duration => finishedAt.difference(startedAt);
}

/// A completed set in a finished workout.
class SetFact {
  const SetFact({
    required this.startedAt,
    required this.exerciseName,
    required this.category,
    required this.weightKg,
    required this.reps,
  });
  final DateTime startedAt;
  final String exerciseName;
  final String category;
  final double weightKg;
  final int reps;

  double get volumeKg => weightKg * reps;
}

class StatsData {
  const StatsData({
    this.workouts = const [],
    this.sets = const [],
    this.bodyweight = const [],
  });
  final List<WorkoutFact> workouts;
  final List<SetFact> sets;
  final List<BodyweightEntry> bodyweight;
}

class StatsRepository {
  StatsRepository(this.db);
  final AppDatabase db;

  /// Only finished workouts count, so an open workout never affects a stat.
  Stream<List<WorkoutFact>> watchWorkouts() =>
      (db.select(db.workouts)..where((w) => w.finishedAt.isNotNull()))
          .watch()
          .map(
            (rows) => [
              for (final w in rows)
                WorkoutFact(startedAt: w.startedAt, finishedAt: w.finishedAt!),
            ],
          );

  /// Only completed sets in finished workouts count.
  Stream<List<SetFact>> watchSets() {
    final query = db.select(db.workoutSets).join([
      innerJoin(
        db.workoutExercises,
        db.workoutExercises.id.equalsExp(db.workoutSets.workoutExerciseId),
      ),
      innerJoin(
        db.workouts,
        db.workouts.id.equalsExp(db.workoutExercises.workoutId),
      ),
      innerJoin(
        db.exercises,
        db.exercises.id.equalsExp(db.workoutExercises.exerciseId),
      ),
    ])..where(
      db.workouts.finishedAt.isNotNull() &
          db.workoutSets.completedAt.isNotNull(),
    );
    return query.watch().map(
      (rows) => [
        for (final row in rows)
          SetFact(
            startedAt: row.readTable(db.workouts).startedAt,
            exerciseName: row.readTable(db.exercises).name,
            category: row.readTable(db.exercises).category,
            weightKg: row.readTable(db.workoutSets).weightKg ?? 0,
            reps: row.readTable(db.workoutSets).reps ?? 0,
          ),
      ],
    );
  }
}

enum StatPeriod {
  week('Week', 12),
  month('Month', 12),
  year('Year', 5);

  const StatPeriod(this.label, this.bucketCount);
  final String label;

  /// How many of the most recent weeks, months or years a chart shows.
  final int bucketCount;
}

class Bucket {
  const Bucket(this.start, this.end, this.label);
  final DateTime start;
  final DateTime end;
  final String label;

  bool contains(DateTime instant) {
    final local = instant.toLocal();
    return !local.isBefore(start) && local.isBefore(end);
  }
}

/// The chart's time slots, oldest first, in local time. Weeks start on Monday.
List<Bucket> bucketsFor(StatPeriod period, DateTime now) {
  final local = now.toLocal();
  final buckets = <Bucket>[];
  for (var i = period.bucketCount - 1; i >= 0; i--) {
    switch (period) {
      case StatPeriod.week:
        final monday = DateTime(
          local.year,
          local.month,
          local.day - (local.weekday - DateTime.monday) - 7 * i,
        );
        final end = DateTime(monday.year, monday.month, monday.day + 7);
        buckets.add(Bucket(monday, end, DateFormat('d/M').format(monday)));
      case StatPeriod.month:
        final start = DateTime(local.year, local.month - i);
        final end = DateTime(start.year, start.month + 1);
        buckets.add(Bucket(start, end, DateFormat('MMM').format(start)));
      case StatPeriod.year:
        final start = DateTime(local.year - i);
        buckets.add(Bucket(start, DateTime(start.year + 1), '${start.year}'));
    }
  }
  return buckets;
}

enum OverallStat {
  workouts('Number of Workouts', isLine: false),
  duration('Workout Duration', isLine: true),
  volume('Volume', isLine: false),
  sets('Total Sets', isLine: false),
  reps('Total Reps', isLine: false),
  repsPerSet('Reps per Set', isLine: true),
  bodyweight('Bodyweight', isLine: true);

  const OverallStat(this.label, {required this.isLine});
  final String label;

  /// Averages and measurements draw as lines, and totals draw as bars.
  final bool isLine;
}

class ChartPoint {
  const ChartPoint(this.label, this.value);
  final String label;

  /// Null when a line chart has no measurement for this slot.
  final double? value;
}

/// One headline number with its caption, such as `1,240 min` / `Total time`.
class StatTile {
  const StatTile(this.caption, this.value);
  final String caption;
  final String value;
}

class StatsCalculator {
  const StatsCalculator(this.data, this.unit);
  final StatsData data;
  final WeightUnit unit;

  int get totalWorkouts => data.workouts.length;

  Duration get totalDuration =>
      data.workouts.fold(Duration.zero, (sum, w) => sum + w.duration);

  double get totalVolumeKg => volumeOf(data.sets);

  int get totalSets => data.sets.length;

  int get totalReps => repsOf(data.sets);

  double get repsPerSet => totalSets == 0 ? 0 : totalReps / totalSets;

  static double volumeOf(Iterable<SetFact> sets) =>
      sets.fold(0, (sum, s) => sum + s.volumeKg);

  static int repsOf(Iterable<SetFact> sets) =>
      sets.fold(0, (sum, s) => sum + s.reps);

  double get _unitPerKg => unit.fromKg(1);

  List<ChartPoint> series(OverallStat stat, StatPeriod period, DateTime now) {
    return [
      for (final bucket in bucketsFor(period, now))
        ChartPoint(bucket.label, _valueIn(stat, bucket)),
    ];
  }

  double? _valueIn(OverallStat stat, Bucket bucket) {
    final workouts = data.workouts.where((w) => bucket.contains(w.startedAt));
    final sets = data.sets.where((s) => bucket.contains(s.startedAt));
    switch (stat) {
      case OverallStat.workouts:
        return workouts.length.toDouble();
      case OverallStat.duration:
        if (workouts.isEmpty) return null;
        final minutes = workouts.fold<int>(
          0,
          (sum, w) => sum + w.duration.inMinutes,
        );
        return minutes / workouts.length;
      case OverallStat.volume:
        return volumeOf(sets) * _unitPerKg;
      case OverallStat.sets:
        return sets.length.toDouble();
      case OverallStat.reps:
        return repsOf(sets).toDouble();
      case OverallStat.repsPerSet:
        if (sets.isEmpty) return null;
        return repsOf(sets) / sets.length;
      case OverallStat.bodyweight:
        final entries = data.bodyweight.where((b) {
          final day = parseDayKey(b.date);
          return !day.isBefore(bucket.start) && day.isBefore(bucket.end);
        }).toList();
        if (entries.isEmpty) return null;
        final sum = entries.fold<double>(0, (s, b) => s + b.weightKg);
        return sum / entries.length * _unitPerKg;
    }
  }

  List<StatTile> tiles(OverallStat stat) {
    switch (stat) {
      case OverallStat.workouts:
        return [StatTile('All time', formatCount(totalWorkouts))];
      case OverallStat.duration:
        final count = totalWorkouts;
        return [
          StatTile('Total time', formatDuration(totalDuration)),
          StatTile(
            'Average',
            count == 0
                ? '-'
                : formatDuration(
                    Duration(minutes: totalDuration.inMinutes ~/ count),
                  ),
          ),
        ];
      case OverallStat.volume:
        return [
          StatTile(
            'All time',
            '${formatCount((totalVolumeKg * _unitPerKg).round())} ${unit.label}',
          ),
        ];
      case OverallStat.sets:
        return [StatTile('All time', formatCount(totalSets))];
      case OverallStat.reps:
        return [StatTile('All time', formatCount(totalReps))];
      case OverallStat.repsPerSet:
        return [StatTile('All time', formatNumber(repsPerSet))];
      case OverallStat.bodyweight:
        if (data.bodyweight.isEmpty) return const [StatTile('Latest', '-')];
        final sorted = [...data.bodyweight]
          ..sort((a, b) => a.date.compareTo(b.date));
        final change = sorted.last.weightKg - sorted.first.weightKg;
        final changeText = formatWeight(change.abs(), unit);
        return [
          StatTile(
            'Latest',
            '${formatWeight(sorted.last.weightKg, unit)} ${unit.label}',
          ),
          StatTile(
            'Change',
            '${change < 0 ? '-' : '+'}$changeText ${unit.label}',
          ),
        ];
    }
  }

  CategoryStats category(String name) =>
      CategoryStats(data.sets.where((s) => s.category == name).toList());

  double unitVolume(double kg) => kg * _unitPerKg;
}

enum CategoryMetric {
  volume('Volume'),
  sets('Sets');

  const CategoryMetric(this.label);
  final String label;
}

class BestSet {
  const BestSet(this.exerciseName, this.weightKg, this.reps);
  final String exerciseName;
  final double weightKg;
  final int reps;
}

class CategoryStats {
  const CategoryStats(this.sets);
  final List<SetFact> sets;

  double get volumeKg => StatsCalculator.volumeOf(sets);

  int get setCount => sets.length;

  /// The best set per exercise: the heaviest, and the most reps at that
  /// weight. Sorted by exercise name.
  List<BestSet> get bestSets {
    final best = <String, SetFact>{};
    for (final set in sets) {
      final current = best[set.exerciseName];
      final better =
          current == null ||
          set.weightKg > current.weightKg ||
          (set.weightKg == current.weightKg && set.reps > current.reps);
      if (better) best[set.exerciseName] = set;
    }
    final names = best.keys.toList()..sort();
    return [
      for (final name in names)
        BestSet(name, best[name]!.weightKg, best[name]!.reps),
    ];
  }

  List<ChartPoint> series(
    CategoryMetric metric,
    StatPeriod period,
    DateTime now,
    WeightUnit unit,
  ) {
    return [
      for (final bucket in bucketsFor(period, now))
        () {
          final inBucket = sets.where((s) => bucket.contains(s.startedAt));
          return ChartPoint(
            bucket.label,
            metric == CategoryMetric.volume
                ? unit.fromKg(StatsCalculator.volumeOf(inBucket))
                : inBucket.length.toDouble(),
          );
        }(),
    ];
  }
}
