import 'package:uuid/uuid.dart';

const categories = [
  'Abs',
  'Back',
  'Biceps',
  'Chest',
  'Legs',
  'Shoulders',
  'Triceps',
];

/// The library a fresh install starts with.
const seedExerciseNames = <String, List<String>>{
  'Abs': ['Cable Crunch', 'Crunch', 'Hanging Leg Raise', 'Plank', 'Sit-Up'],
  'Back': [
    'Barbell Row',
    'Chest Supported Row',
    'Deadlift',
    'Dumbbell Row',
    'Lat Pulldown',
    'Pull-Up',
    'Seated Cable Row',
  ],
  'Biceps': [
    'Barbell Curl',
    'Cable Curl',
    'Dumbbell Curl',
    'Hammer Curl',
    'Preacher Curl',
  ],
  'Chest': [
    'Bench Press',
    'Cable Fly',
    'Chest Dip',
    'Dumbbell Bench Press',
    'Incline Bench Press',
    'Incline Dumbbell Press',
    'Machine Chest Press',
    'Push-Up',
  ],
  'Legs': [
    'Bulgarian Split Squat',
    'Hip Thrust',
    'Leg Curl',
    'Leg Extension',
    'Leg Press',
    'Romanian Deadlift',
    'Squat',
    'Standing Calf Raise',
  ],
  'Shoulders': [
    'Cable Lateral Raise',
    'Dumbbell Lateral Raise',
    'Face Pull',
    'Overhead Press',
    'Rear Delt Fly',
    'Shoulder Dumbbell Press',
  ],
  'Triceps': [
    'Close Grip Bench Press',
    'Overhead Tricep Extension',
    'Skull Crusher',
    'Tricep Dip',
    'Tricep Pushdown',
  ],
};

/// A stable ID for an exercise name, so a seeded exercise has the same ID on
/// every install and in every export.
String exerciseIdFor(String name) =>
    const Uuid().v5(Namespace.url.value, 'hakwat:exercise:$name');
