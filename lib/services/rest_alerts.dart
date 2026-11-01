import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// The notification that fires when a rest ends, including on a locked phone.
class RestAlerts {
  static const _notificationId = 1;

  final _plugin = FlutterLocalNotificationsPlugin();
  Future<void>? _ready;
  int _latestRequest = 0;

  Future<void> _ensureReady() => _ready ??= _init();

  Future<void> _init() async {
    tz_data.initializeTimeZones();
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  /// Asks for the notification permission. Android only shows the prompt until
  /// the user has answered.
  Future<void> requestPermission() async {
    try {
      await _ensureReady();
      await _android?.requestNotificationsPermission();
    } on PlatformException catch (error) {
      debugPrint('Notification permission request failed: $error');
    }
  }

  Future<void> schedule(DateTime at) async {
    final request = ++_latestRequest;
    try {
      await requestPermission();
      // The permission prompt can stay up for a while. If the rest was skipped
      // or restarted meanwhile, this alert is out of date.
      if (request != _latestRequest) return;
      await _plugin.cancel(id: _notificationId);
      await _plugin.zonedSchedule(
        id: _notificationId,
        scheduledDate: tz.TZDateTime.from(at.toUtc(), tz.UTC),
        title: 'Rest is over',
        body: 'Time for your next set.',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'rest_timer',
            'Rest timer',
            channelDescription: 'Tells you when your rest between sets ends',
            importance: Importance.high,
            priority: Priority.high,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      );
    } on PlatformException catch (error) {
      // A missing alert must never get in the way of logging a set.
      debugPrint('Could not schedule the rest alert: $error');
    }
  }

  Future<void> cancel() async {
    _latestRequest++;
    try {
      await _ensureReady();
      await _plugin.cancel(id: _notificationId);
    } on PlatformException catch (error) {
      debugPrint('Could not cancel the rest alert: $error');
    }
  }
}
