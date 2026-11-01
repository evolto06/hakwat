// Writes assets/dev/mock_data.json. Run with: dart run tool/generate_mock_data.dart
//
// The output is the same format as a real export, and the same input always
// gives the same file. The first section matches the mockup exactly. Weights,
// reps, the cut-off routines and the rest of the history are invented.
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:hakwat/data/seed_exercises.dart';
import 'package:uuid/uuid.dart';

const fly = 'Tony Machine Fly';
const pulldown = 'Tonys Single Arm Lat Pulldown';
const shoulderPress = 'Shoulder Dumbbell Press';
const curls = 'Recline Curls';
const pushdown = 'Tonys Straight Bar Pushdown';
const latRaise = 'Tonys Cable Lat Raise';
const inclinePress = 'Incline Dumbbell Press';

/// Custom exercises from the mockup, with their categories.
const customExercises = {
  fly: 'Chest',
  pulldown: 'Back',
  curls: 'Biceps',
  pushdown: 'Triceps',
  latRaise: 'Shoulders',
};

/// Routines in mockup order. The last two rows are cut off in the mockup, so
/// they use the two routine names seen on the log cards.
const routines = <String, List<(String, int)>>{
  'Gladiator Upper': [
    ('Bench Press', 3),
    ('Barbell Row', 3),
    ('Overhead Press', 3),
    ('Barbell Curl', 2),
    ('Skull Crusher', 2),
  ],
  'Tonys Upper SARMS Focus': [
    (fly, 2),
    (pulldown, 2),
    (shoulderPress, 2),
    (latRaise, 2),
    (curls, 1),
    (pushdown, 1),
  ],
  'Tonys Legs B': [
    ('Romanian Deadlift', 3),
    ('Leg Curl', 2),
    ('Bulgarian Split Squat', 2),
    ('Standing Calf Raise', 2),
  ],
  'Tonys Upper A': [
    (shoulderPress, 1),
    (pulldown, 2),
    (inclinePress, 2),
    (curls, 1),
    (latRaise, 1),
  ],
  'Tonys Upper B': [
    (inclinePress, 2),
    (fly, 1),
    (pulldown, 2),
    (shoulderPress, 1),
    (pushdown, 1),
  ],
  'Tonys Legs': [
    ('Squat', 3),
    ('Leg Press', 2),
    ('Leg Extension', 2),
    ('Leg Curl', 2),
  ],
  'Tony Chest': [(inclinePress, 3), (fly, 3), ('Chest Dip', 2)],
  'Tonys Back': [
    (pulldown, 3),
    ('Chest Supported Row', 3),
    ('Seated Cable Row', 2),
  ],
  'Full Body': [
    ('Squat', 2),
    ('Bench Press', 2),
    ('Barbell Row', 2),
    ('Overhead Press', 2),
    ('Plank', 2),
  ],
  'Legs': [('Squat', 3), ('Romanian Deadlift', 2), ('Leg Press', 2)],
  'Tonys Upper C': [
    (pulldown, 1),
    (inclinePress, 2),
    (shoulderPress, 1),
    (fly, 1),
    (curls, 1),
    (pushdown, 1),
  ],
  'Tonys Upper Minimalist': [
    (fly, 2),
    (pulldown, 1),
    (shoulderPress, 1),
    (curls, 1),
    (pushdown, 1),
    (latRaise, 1),
  ],
};

/// Starting working weight in kg and typical reps.
const baselines = <String, (double, int)>{
  fly: (40, 12),
  pulldown: (35, 10),
  shoulderPress: (20, 10),
  curls: (10, 12),
  pushdown: (30, 12),
  latRaise: (7.5, 15),
  inclinePress: (24, 10),
  'Bench Press': (70, 8),
  'Barbell Row': (60, 8),
  'Overhead Press': (40, 8),
  'Barbell Curl': (30, 10),
  'Skull Crusher': (25, 10),
  'Romanian Deadlift': (80, 8),
  'Leg Curl': (40, 12),
  'Bulgarian Split Squat': (20, 10),
  'Standing Calf Raise': (60, 15),
  'Squat': (90, 6),
  'Leg Press': (140, 10),
  'Leg Extension': (50, 12),
  'Chest Dip': (0, 12),
  'Chest Supported Row': (30, 10),
  'Seated Cable Row': (55, 10),
  'Plank': (0, 1),
};

class PlannedWorkout {
  const PlannedWorkout(
    this.date,
    this.routine,
    this.exercises, {
    this.minutes,
    this.open = false,
  });
  final DateTime date;
  final String routine;

  /// Exercise, completed sets.
  final List<(String, int)> exercises;

  final int? minutes;
  final bool open;
}

/// The four cards the mockup shows. Oct 15's list is cut off after the first
/// exercise, so the rest of it comes from the routine.
final mockupWorkouts = [
  PlannedWorkout(DateTime.utc(2026, 10, 30), 'Tonys Upper Minimalist', const [
    (fly, 2),
    (pulldown, 1),
    (shoulderPress, 1),
    (curls, 1),
    (pushdown, 1),
    (latRaise, 1),
  ], open: true),
  PlannedWorkout(DateTime.utc(2026, 10, 22), 'Tonys Upper C', const [
    (pulldown, 1),
    (inclinePress, 2),
    (shoulderPress, 1),
    (fly, 1),
    (curls, 1),
    (pushdown, 1),
  ], minutes: 107),
  PlannedWorkout(DateTime.utc(2026, 10, 18), 'Tonys Upper C', const [
    (pulldown, 1),
    (inclinePress, 2),
    (shoulderPress, 1),
    (fly, 1),
    (curls, 1),
  ], minutes: 33),
  PlannedWorkout(
    DateTime.utc(2026, 10, 15),
    'Tonys Upper A',
    routines['Tonys Upper A']!,
    minutes: 64,
  ),
];

const uuid = Uuid();
String idFor(String key) => uuid.v5(Namespace.url.value, 'hakwat:mock:$key');

String time(DateTime value) => value.toUtc().toIso8601String();

void main() {
  final random = Random(20261101);

  // October has 8 workouts in the mockup: the 4 visible ones plus these 4, then
  // August and September fill out three months of history.
  const rotation = [
    'Tonys Upper A',
    'Tonys Legs',
    'Tonys Upper B',
    'Tonys Back',
    'Tony Chest',
    'Tonys Legs B',
    'Tonys Upper SARMS Focus',
    'Full Body',
    'Gladiator Upper',
    'Legs',
  ];
  final historyDates = <DateTime>[
    ...[12, 8, 5, 1].map((d) => DateTime.utc(2026, 10, d)),
    ...[28, 24, 21, 17, 14, 10, 7, 3].map((d) => DateTime.utc(2026, 9, d)),
    ...[31, 27, 24, 20, 17, 13, 10, 6, 3].map((d) => DateTime.utc(2026, 8, d)),
  ];
  final planned = [
    ...mockupWorkouts,
    for (final (i, date) in historyDates.indexed)
      PlannedWorkout(
        date,
        rotation[i % rotation.length],
        routines[rotation[i % rotation.length]]!,
        minutes: 45 + random.nextInt(50),
      ),
  ];

  final first = DateTime.utc(2026, 8, 3);
  final last = DateTime.utc(2026, 10, 30);
  final span = last.difference(first).inDays;

  // Weights climb gradually over the three months, in 2.5 kg plate steps.
  double weightOn(String exercise, DateTime date) {
    final base = baselines[exercise]?.$1 ?? 20;
    if (base == 0) return 0;
    final progress = date.difference(first).inDays / span;
    final raw = base * (1 + 0.15 * progress);
    return (raw / 2.5).round() * 2.5;
  }

  final workouts = <Map<String, dynamic>>[];
  for (final plan in planned) {
    final key = '${plan.date.toIso8601String()}|${plan.routine}';
    // 10:00 UTC keeps the same calendar day across nearly every time zone.
    final startedAt = plan.date.add(const Duration(hours: 10));
    final totalSets = plan.exercises.fold<int>(0, (s, e) => s + e.$2);
    final minutes = plan.minutes ?? 30;
    var setIndex = 0;

    final exercises = <Map<String, dynamic>>[];
    for (final (order, (exercise, count)) in plan.exercises.indexed) {
      final linkKey = '$key|$order';
      final baseReps = baselines[exercise]?.$2 ?? 10;
      final weight = weightOn(exercise, plan.date);
      final sets = <Map<String, dynamic>>[];
      for (var s = 0; s < count; s++) {
        setIndex++;
        sets.add({
          'id': idFor('$linkKey|set$s'),
          'sortOrder': s,
          'weightKg': weight,
          'reps': baseReps > 1 ? max(1, baseReps - s - random.nextInt(2)) : 1,
          'completedAt': time(
            startedAt.add(
              Duration(seconds: (minutes * 60 * setIndex / totalSets).round()),
            ),
          ),
        });
      }
      // The open workout has one set still to do, so resuming shows a row
      // ready to fill in.
      if (plan.open && exercise == latRaise) {
        sets.add({
          'id': idFor('$linkKey|set$count'),
          'sortOrder': count,
          'weightKg': null,
          'reps': null,
          'completedAt': null,
        });
      }
      exercises.add({
        'id': idFor(linkKey),
        'exerciseId': exerciseIdFor(exercise),
        'sortOrder': order,
        'sets': sets,
      });
    }

    workouts.add({
      'id': idFor(key),
      'routineId': idFor('routine|${plan.routine}'),
      'name': plan.routine,
      'startedAt': time(startedAt),
      'finishedAt': plan.open
          ? null
          : time(startedAt.add(Duration(minutes: minutes))),
      'exercises': exercises,
    });
  }

  // Bodyweight twice a week, drifting from 82 kg down to about 79.5 kg.
  final bodyweight = <Map<String, dynamic>>[];
  for (var day = 0; day <= span; day += 3 + (day % 2)) {
    final date = first.add(Duration(days: day));
    final trend = 82 - 2.5 * day / span;
    final noise = (random.nextDouble() - 0.5) * 0.6;
    final key = date.toIso8601String().substring(0, 10);
    bodyweight.add({
      'id': idFor('bodyweight|$key'),
      'date': key,
      'weightKg': double.parse((trend + noise).toStringAsFixed(1)),
    });
  }

  final exercises = <Map<String, dynamic>>[
    for (final entry in seedExerciseNames.entries)
      for (final name in entry.value)
        {
          'id': exerciseIdFor(name),
          'name': name,
          'category': entry.key,
          'isCustom': false,
          'archivedAt': null,
        },
    for (final entry in customExercises.entries)
      {
        'id': exerciseIdFor(entry.key),
        'name': entry.key,
        'category': entry.value,
        'isCustom': true,
        'archivedAt': null,
      },
  ];

  final file = {
    'app': 'hakwat',
    'schemaVersion': 1,
    'exportedAt': '2026-11-01T00:00:00.000Z',
    'exercises': exercises,
    'routines': [
      for (final (order, entry) in routines.entries.indexed)
        {
          'id': idFor('routine|${entry.key}'),
          'name': entry.key,
          'sortOrder': order,
          'exercises': [
            for (final (i, (exercise, target)) in entry.value.indexed)
              {
                'id': idFor('routine|${entry.key}|$i'),
                'exerciseId': exerciseIdFor(exercise),
                'sortOrder': i,
                'targetSets': target,
              },
          ],
        },
    ],
    'workouts': workouts,
    'bodyweight': bodyweight,
    'settings': <String, String>{},
  };

  File('assets/dev/mock_data.json')
    ..createSync(recursive: true)
    ..writeAsStringSync(const JsonEncoder.withIndent(' ').convert(file));
  stdout.writeln(
    'Wrote ${workouts.length} workouts, ${routines.length} routines, '
    '${bodyweight.length} bodyweight entries.',
  );
}
