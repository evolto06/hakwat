import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hakwat/app/providers.dart';
import 'package:hakwat/data/backup.dart';
import 'package:hakwat/data/database.dart';
import 'package:hakwat/data/library_repositories.dart';
import 'package:hakwat/main.dart';
import 'package:hakwat/services/rest_alerts.dart';

class FakeRestAlerts extends RestAlerts {
  final scheduled = <DateTime>[];
  int cancels = 0;

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> schedule(DateTime at) async => scheduled.add(at);

  @override
  Future<void> cancel() async => cancels++;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final mock = File('assets/dev/mock_data.json').readAsStringSync();

  late AppDatabase db;
  late FakeRestAlerts alerts;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    alerts = FakeRestAlerts();
  });

  Future<void> pumpApp(WidgetTester tester, {bool loadMock = true}) async {
    tester.view.physicalSize = const Size(1080, 2340);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    if (loadMock) {
      await tester.runAsync(() => replaceAllData(db, parseBackup(mock)));
    }
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          databaseProvider.overrideWith((ref) => db),
          restAlertsProvider.overrideWith((ref) => alerts),
        ],
        child: const HakwatApp(),
      ),
    );
    await settle(tester);
  }

  testWidgets('empty states on a fresh install', (tester) async {
    await pumpApp(tester, loadMock: false);
    expect(find.text('No workouts yet'), findsOneWidget);
    expect(find.text('Start Workout'), findsOneWidget);

    await tester.tap(find.text('Routines'));
    await settle(tester);
    expect(find.text('No routines yet'), findsOneWidget);
    expect(find.text('Start Workout'), findsOneWidget);
    await closeApp(tester, db);
  });

  testWidgets('the Log tab matches the mockup', (tester) async {
    await pumpApp(tester);
    expect(find.text('October'), findsOneWidget);
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('8 workouts'), findsOneWidget);
    expect(find.text('Tonys Upper Minimalist'), findsOneWidget);
    expect(find.text('2x Tony Machine Fly'), findsWidgets);
    expect(find.text('1x Tonys Cable Lat Raise'), findsWidgets);
    expect(find.text('107 min'), findsOneWidget);
    expect(find.text('33 min'), findsOneWidget);
    expect(find.text('FRI'), findsWidgets);
    expect(find.text('30'), findsWidgets);
    expect(find.text('Resume Workout'), findsOneWidget);
    await closeApp(tester, db);
  });

  testWidgets('the app bar follows the month in view', (tester) async {
    await pumpApp(tester);
    final list = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('September 2026'),
      300,
      scrollable: list.first,
    );
    await tester.drag(list.first, const Offset(0, -700));
    await settle(tester);
    expect(
      find.descendant(of: find.byType(AppBar), matching: find.text('September')),
      findsOneWidget,
    );
    await closeApp(tester, db);
  });

  testWidgets('the Routines tab lists routines in mockup order', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Routines'));
    await settle(tester);
    final titles = [
      'Gladiator Upper',
      'Tonys Upper SARMS Focus',
      'Tonys Legs B',
      'Tonys Upper A',
      'Tonys Upper B',
      'Tonys Legs',
      'Tony Chest',
      'Tonys Back',
      'Full Body',
    ];
    double? lastY;
    for (final title in titles) {
      final y = tester.getTopLeft(find.text(title)).dy;
      if (lastY != null) expect(y, greaterThan(lastY));
      lastY = y;
    }
    expect(find.byIcon(Icons.more_horiz), findsWidgets);
    await closeApp(tester, db);
  });

  testWidgets('routine menus open above the Start/Resume button', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Routines'));
    await settle(tester);

    await tester.tap(find.byTooltip('Routine options').first);
    await settle(tester);
    final root = tester.state<NavigatorState>(find.byType(Navigator).first);
    expect(Navigator.of(tester.element(find.text('Duplicate'))), root);

    await tester.tap(find.text('Delete'));
    await settle(tester);
    expect(find.text('Delete Gladiator Upper?'), findsOneWidget);
    await tester.tap(find.text('Delete').last);
    await settle(tester);
    expect(find.text('Gladiator Upper'), findsNothing);
    await closeApp(tester, db);
  });

  testWidgets('the Statistics tab has chevrons, not locks', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Statistics'));
    await settle(tester);
    expect(find.text('Overall Statistics'), findsOneWidget);
    expect(find.text('Number of Workouts'), findsOneWidget);
    expect(find.text('Bodyweight'), findsOneWidget);
    expect(find.byIcon(Icons.lock), findsNothing);
    expect(find.byIcon(Icons.chevron_right), findsWidgets);

    await tester.tap(find.text('Volume'));
    await settle(tester);
    expect(find.text('kg lifted per month'), findsOneWidget);
    await closeApp(tester, db);
  });

  testWidgets('logging a set saves it, starts the rest timer and finishes', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Resume Workout'));
    await settle(tester);

    expect(find.text('Tonys Upper Minimalist'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Tonys Cable Lat Raise'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await settle(tester);

    // The last row of the Lat Raise card is the one incomplete set in the file.
    final fields = find.byType(TextField);
    await tester.enterText(fields.at(fields.evaluate().length - 2), '12.5');
    await tester.enterText(fields.last, '11');
    await settle(tester);

    final saved = await tester.runAsync(
      () =>
          (db.select(db.workoutSets)
                ..where((s) => s.completedAt.isNull()))
              .getSingle(),
    );
    expect(saved!.weightKg, 12.5, reason: 'saved before the set is ticked');
    expect(saved.reps, 11);

    await tester.tap(find.byTooltip('Mark set 2 done').last);
    await settle(tester);
    expect(alerts.scheduled, hasLength(1));
    expect(find.text('Skip'), findsOneWidget);

    await tester.tap(find.text('Skip'));
    await settle(tester);
    expect(find.text('Skip'), findsNothing);
    expect(alerts.cancels, greaterThan(0));

    await tester.tap(find.text('Finish'));
    await settle(tester);
    await tester.tap(find.text('Finish').last);
    await settle(tester);

    expect(find.text('Start Workout'), findsOneWidget);
    expect(find.text('2x Tonys Cable Lat Raise'), findsOneWidget);
    await closeApp(tester, db);
  });

  testWidgets('switching units updates what the screens show', (tester) async {
    await tester.runAsync(() async {
      await replaceAllData(db, parseBackup(mock));
      await SettingsRepository(db).set(AppSettings.unitKey, 'lb');
    });
    await pumpApp(tester, loadMock: false);
    await tester.tap(find.text('Statistics'));
    await settle(tester);
    await tester.tap(find.text('Volume'));
    await settle(tester);
    expect(find.text('lb lifted per month'), findsOneWidget);
    await closeApp(tester, db);
  });

  testWidgets('dev tools appear in the drawer in debug builds', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Menu').first);
    await settle(tester);
    expect(find.text('Exercises'), findsOneWidget);
    expect(find.text('Export and restore'), findsOneWidget);
    expect(find.text('Dev tools'), findsOneWidget);

    await tester.tap(find.text('Clear all data'));
    await settle(tester);
    expect(find.text('No workouts yet'), findsOneWidget);
    await closeApp(tester, db);
  });
}

/// Lets database work on real timers finish, then runs the resulting frames.
/// The workout clock ticks forever, so `pumpAndSettle` would never return.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
  await tester.pump(const Duration(milliseconds: 400));
}

/// Tears the app down inside the test so the database's own cleanup timers
/// finish before the test framework checks for pending ones.
Future<void> closeApp(WidgetTester tester, AppDatabase db) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester);
  await tester.runAsync(db.close);
  await tester.pump(const Duration(seconds: 1));
}
