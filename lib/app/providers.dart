import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/library_repositories.dart';
import '../data/stats.dart';
import '../data/workout_repository.dart';
import '../services/rest_alerts.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

final workoutRepositoryProvider = Provider(
  (ref) => WorkoutRepository(ref.watch(databaseProvider)),
);
final routineRepositoryProvider = Provider(
  (ref) => RoutineRepository(ref.watch(databaseProvider)),
);
final exerciseRepositoryProvider = Provider(
  (ref) => ExerciseRepository(ref.watch(databaseProvider)),
);
final bodyweightRepositoryProvider = Provider(
  (ref) => BodyweightRepository(ref.watch(databaseProvider)),
);
final settingsRepositoryProvider = Provider(
  (ref) => SettingsRepository(ref.watch(databaseProvider)),
);
final statsRepositoryProvider = Provider(
  (ref) => StatsRepository(ref.watch(databaseProvider)),
);

final openWorkoutProvider = StreamProvider<Workout?>(
  (ref) => ref.watch(workoutRepositoryProvider).watchOpen(),
);
final logProvider = StreamProvider<List<WorkoutSummary>>(
  (ref) => ref.watch(workoutRepositoryProvider).watchLog(),
);
final workoutDetailProvider = StreamProvider.autoDispose
    .family<WorkoutDetail?, String>(
      (ref, id) => ref.watch(workoutRepositoryProvider).watchDetail(id),
    );

/// Sets from the last time this exercise was done before the given time.
final previousSetsProvider = FutureProvider.autoDispose
    .family<List<WorkoutSet>, (String, DateTime)>(
      (ref, key) => ref
          .watch(workoutRepositoryProvider)
          .previousSets(key.$1, before: key.$2),
    );

final routinesProvider = StreamProvider<List<Routine>>(
  (ref) => ref.watch(routineRepositoryProvider).watchAll(),
);
final routineDetailProvider = StreamProvider.autoDispose
    .family<RoutineDetail?, String>(
      (ref, id) => ref.watch(routineRepositoryProvider).watchDetail(id),
    );

final exercisesProvider = StreamProvider<List<Exercise>>(
  (ref) => ref.watch(exerciseRepositoryProvider).watchAll(),
);
final bodyweightProvider = StreamProvider<List<BodyweightEntry>>(
  (ref) => ref.watch(bodyweightRepositoryProvider).watchAll(),
);

final _settingsStreamProvider = StreamProvider<AppSettings>(
  (ref) => ref.watch(settingsRepositoryProvider).watch(),
);

/// Current settings, with defaults until the first read has finished.
final settingsProvider = Provider<AppSettings>(
  (ref) => ref.watch(_settingsStreamProvider).value ?? const AppSettings(),
);

final _statWorkoutsProvider = StreamProvider<List<WorkoutFact>>(
  (ref) => ref.watch(statsRepositoryProvider).watchWorkouts(),
);
final _statSetsProvider = StreamProvider<List<SetFact>>(
  (ref) => ref.watch(statsRepositoryProvider).watchSets(),
);

final statsDataProvider = Provider<StatsData>(
  (ref) => StatsData(
    workouts: ref.watch(_statWorkoutsProvider).value ?? const [],
    sets: ref.watch(_statSetsProvider).value ?? const [],
    bodyweight: ref.watch(bodyweightProvider).value ?? const [],
  ),
);

final restAlertsProvider = Provider<RestAlerts>((ref) => RestAlerts());

/// The time the current rest ends, or null when nothing is counting down.
final restTimerProvider = NotifierProvider<RestTimerController, DateTime?>(
  RestTimerController.new,
);

class RestTimerController extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void start(int seconds) {
    if (seconds <= 0) {
      stop();
      return;
    }
    _setEnd(DateTime.now().add(Duration(seconds: seconds)));
  }

  /// Adds or removes time. Taking off more than remains ends the rest.
  void adjust(int seconds) {
    final end = state;
    if (end == null) return;
    final next = end.add(Duration(seconds: seconds));
    if (next.isAfter(DateTime.now())) {
      _setEnd(next);
    } else {
      stop();
    }
  }

  void stop() {
    state = null;
    ref.read(restAlertsProvider).cancel();
  }

  /// Clears a rest that ran out on its own. The alert has already gone off.
  void expire() => state = null;

  void _setEnd(DateTime end) {
    state = end;
    if (ref.read(settingsProvider).restAlert) {
      ref.read(restAlertsProvider).schedule(end);
    } else {
      ref.read(restAlertsProvider).cancel();
    }
  }
}
