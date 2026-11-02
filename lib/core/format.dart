import 'package:intl/intl.dart';

enum WeightUnit {
  kg('kg'),
  lb('lb');

  const WeightUnit(this.label);
  final String label;

  static const _lbPerKg = 2.20462262185;

  double fromKg(double value) => this == kg ? value : value * _lbPerKg;
  double toKg(double value) => this == kg ? value : value / _lbPerKg;

  static WeightUnit parse(String? value) =>
      value == WeightUnit.lb.name ? WeightUnit.lb : WeightUnit.kg;
}

/// How an exercise's sets are logged. An exercise with no mode follows the
/// app's weight unit setting.
enum WeightMode {
  kg('kg'),
  lb('lb'),

  /// Unlabeled stacks: the set records the pin position instead of a weight.
  pin('Pin number');

  const WeightMode(this.label);
  final String label;
}

/// How much each pin hole is assumed to add unless the setting says otherwise.
const defaultPinIncrementLb = 10;

/// A rough weight for a pin position, used only for volume. Real stacks vary,
/// so anything showing a number built from this also shows a disclaimer.
double pinWeightKg(int pin, int incrementLb) =>
    WeightUnit.lb.toKg((pin * incrementLb).toDouble());

/// The unit a weight is shown in for an exercise with this mode.
WeightUnit unitForMode(WeightMode? mode, WeightUnit appUnit) => switch (mode) {
  WeightMode.kg => WeightUnit.kg,
  WeightMode.lb => WeightUnit.lb,
  _ => appUnit,
};

/// `Pin 7` or `60 kg`, for a set whose load is being read rather than typed.
String formatLoad(double? weightKg, int? pin, WeightUnit unit) => pin != null
    ? 'Pin $pin'
    : '${formatWeight(weightKg ?? 0, unit)} ${unit.label}';

/// `Chest Fly · Tonys Gym`, or just the name for an exercise with no gym.
String exerciseLabel(String name, String? gymName) =>
    gymName == null ? name : '$name · $gymName';

/// `60`, `62.5`, `61.2`: at most one decimal, with no trailing zero.
String formatNumber(double value) {
  final rounded = (value * 10).round() / 10;
  if (rounded == rounded.roundToDouble()) return rounded.toInt().toString();
  return rounded.toStringAsFixed(1);
}

/// A weight in the user's unit, without the unit label.
String formatWeight(double kg, WeightUnit unit) =>
    formatNumber(unit.fromKg(kg));

/// `12,450`, for totals.
String formatCount(num value) => NumberFormat.decimalPattern().format(value);

/// `107 min`, or `2 h 5 min` once it's long enough to be easier to read that way.
String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 180) return '$minutes min';
  return '${minutes ~/ 60} h ${minutes % 60} min';
}

/// `12:05` or `1:02:45`, for the running workout clock.
String formatClock(Duration duration) {
  final total = duration.isNegative ? Duration.zero : duration;
  final hours = total.inHours;
  final minutes = total.inMinutes % 60;
  final seconds = (total.inSeconds % 60).toString().padLeft(2, '0');
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// `6:00 PM to 7:47 PM`, adding the end date when a workout ran past midnight.
String formatTimeRange(DateTime localStart, DateTime localEnd) {
  final time = DateFormat.jm();
  final sameDay =
      localStart.year == localEnd.year &&
      localStart.month == localEnd.month &&
      localStart.day == localEnd.day;
  final end = sameDay
      ? time.format(localEnd)
      : '${DateFormat.MMMd().format(localEnd)}, ${time.format(localEnd)}';
  return '${time.format(localStart)} to $end';
}

String formatDayKey(DateTime localDate) =>
    DateFormat('yyyy-MM-dd').format(localDate);

DateTime parseDayKey(String key) => DateFormat('yyyy-MM-dd').parseStrict(key);
