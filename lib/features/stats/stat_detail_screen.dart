import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/stats.dart';

class OverallStatScreen extends ConsumerStatefulWidget {
  const OverallStatScreen({super.key, required this.statName});
  final String statName;

  @override
  ConsumerState<OverallStatScreen> createState() => _OverallStatScreenState();
}

class _OverallStatScreenState extends ConsumerState<OverallStatScreen> {
  StatPeriod _period = StatPeriod.month;

  @override
  Widget build(BuildContext context) {
    final stat = OverallStat.values.byName(widget.statName);
    final unit = ref.watch(settingsProvider).unit;
    final calculator = StatsCalculator(ref.watch(statsDataProvider), unit);
    final points = calculator.series(stat, _period, DateTime.now());

    return Scaffold(
      appBar: AppBar(
        title: Text(stat.label),
        actions: [
          if (stat == OverallStat.bodyweight)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Bodyweight entries',
              onPressed: () => context.push('/bodyweight'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _PeriodPicker(
            period: _period,
            onChanged: (period) => setState(() => _period = period),
          ),
          const SizedBox(height: 16),
          _TileRow(tiles: calculator.tiles(stat)),
          const SizedBox(height: 16),
          _ChartCard(
            caption: _caption(stat, unit),
            points: points,
            isLine: stat.isLine,
          ),
        ],
      ),
    );
  }

  String _caption(OverallStat stat, WeightUnit unit) {
    final per = _period.label.toLowerCase();
    return switch (stat) {
      OverallStat.workouts => 'Workouts per $per',
      OverallStat.duration => 'Average minutes per workout, by $per',
      OverallStat.volume => '${unit.label} lifted per $per',
      OverallStat.sets => 'Sets per $per',
      OverallStat.reps => 'Reps per $per',
      OverallStat.repsPerSet => 'Average reps per set, by $per',
      OverallStat.bodyweight => 'Average ${unit.label}, by $per',
    };
  }
}

class CategoryStatScreen extends ConsumerStatefulWidget {
  const CategoryStatScreen({super.key, required this.category});
  final String category;

  @override
  ConsumerState<CategoryStatScreen> createState() => _CategoryStatScreenState();
}

class _CategoryStatScreenState extends ConsumerState<CategoryStatScreen> {
  StatPeriod _period = StatPeriod.month;
  CategoryMetric _metric = CategoryMetric.volume;

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider).unit;
    final stats = StatsCalculator(
      ref.watch(statsDataProvider),
      unit,
    ).category(widget.category);
    final points = stats.series(_metric, _period, DateTime.now(), unit);
    final per = _period.label.toLowerCase();

    return Scaffold(
      appBar: AppBar(title: Text(widget.category)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _PeriodPicker(
            period: _period,
            onChanged: (period) => setState(() => _period = period),
          ),
          const SizedBox(height: 16),
          _TileRow(
            tiles: [
              StatTile(
                'Volume',
                '${formatCount(unit.fromKg(stats.volumeKg).round())} ${unit.label}',
              ),
              StatTile('Sets', formatCount(stats.setCount)),
            ],
          ),
          const SizedBox(height: 16),
          SegmentedButton<CategoryMetric>(
            showSelectedIcon: false,
            segments: [
              for (final metric in CategoryMetric.values)
                ButtonSegment(value: metric, label: Text(metric.label)),
            ],
            selected: {_metric},
            onSelectionChanged: (value) =>
                setState(() => _metric = value.single),
          ),
          const SizedBox(height: 16),
          _ChartCard(
            caption: _metric == CategoryMetric.volume
                ? '${unit.label} lifted per $per'
                : 'Sets per $per',
            points: points,
            isLine: false,
          ),
          const SizedBox(height: 24),
          const Text(
            'Best sets',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          if (stats.bestSets.isEmpty)
            const Text(
              'No completed sets in this category yet.',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          for (final best in stats.bestSets)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(child: Text(best.exerciseName)),
                  const SizedBox(width: 12),
                  Text(
                    '${formatWeight(best.weightKg, unit)} ${unit.label} '
                    '× ${best.reps}',
                    style: const TextStyle(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _PeriodPicker extends StatelessWidget {
  const _PeriodPicker({required this.period, required this.onChanged});
  final StatPeriod period;
  final ValueChanged<StatPeriod> onChanged;

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<StatPeriod>(
      showSelectedIcon: false,
      segments: [
        for (final value in StatPeriod.values)
          ButtonSegment(value: value, label: Text(value.label)),
      ],
      selected: {period},
      onSelectionChanged: (value) => onChanged(value.single),
    );
  }
}

class _TileRow extends StatelessWidget {
  const _TileRow({required this.tiles});
  final List<StatTile> tiles;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final tile in tiles)
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tile.caption,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(tile.value, style: const TextStyle(fontSize: 22)),
              ],
            ),
          ),
      ],
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.caption,
    required this.points,
    required this.isLine,
  });

  final String caption;
  final List<ChartPoint> points;
  final bool isLine;

  bool get _hasData => points.any((p) => (p.value ?? 0) != 0);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 16, 16, 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 16),
            child: Text(
              caption,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          SizedBox(
            height: 240,
            child: !_hasData
                ? const Center(
                    child: Text(
                      'No data for this period',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : isLine
                ? _LineChart(points: points)
                : _BarChart(points: points),
          ),
        ],
      ),
    );
  }
}

const _axisStyle = TextStyle(fontSize: 10, color: AppColors.textSecondary);

String _compact(double value) {
  if (value.abs() >= 1000) return NumberFormat.compact().format(value);
  return formatNumber(value);
}

/// Shows every label when they fit, and every other one, counted back from the
/// newest, when they don't.
Widget _bottomLabel(List<ChartPoint> points, double value) {
  final index = value.round();
  if (index < 0 || index >= points.length || value != index.toDouble()) {
    return const SizedBox.shrink();
  }
  final step = points.length > 6 ? 2 : 1;
  if ((points.length - 1 - index) % step != 0) return const SizedBox.shrink();
  return Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Text(points[index].label, style: _axisStyle),
  );
}

/// The nearest 1, 2, 2.5 or 5 step (times a power of ten) at or above [value],
/// so axis labels land on round numbers.
double _niceStep(double value) {
  if (value <= 0) return 1;
  final magnitude = math
      .pow(10, (math.log(value) / math.ln10).floor())
      .toDouble();
  final scaled = value / magnitude;
  final step = scaled <= 1
      ? 1.0
      : scaled <= 2
      ? 2.0
      : scaled <= 2.5
      ? 2.5
      : scaled <= 5
      ? 5.0
      : 10.0;
  return step * magnitude;
}

FlTitlesData _titles(List<ChartPoint> points, double? interval) {
  const hidden = AxisTitles(sideTitles: SideTitles(showTitles: false));
  return FlTitlesData(
    topTitles: hidden,
    rightTitles: hidden,
    leftTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        reservedSize: 36,
        interval: interval,
        getTitlesWidget: (value, meta) => SideTitleWidget(
          meta: meta,
          child: Text(_compact(value), style: _axisStyle),
        ),
      ),
    ),
    bottomTitles: AxisTitles(
      sideTitles: SideTitles(
        showTitles: true,
        interval: 1,
        reservedSize: 26,
        getTitlesWidget: (value, _) => _bottomLabel(points, value),
      ),
    ),
  );
}

FlGridData _grid(double? interval) => FlGridData(
  drawVerticalLine: false,
  horizontalInterval: interval,
  getDrawingHorizontalLine: (_) =>
      const FlLine(color: AppColors.navPill, strokeWidth: 1),
);

class _BarChart extends StatelessWidget {
  const _BarChart({required this.points});
  final List<ChartPoint> points;

  bool get wholeSteps =>
      points.every((p) => (p.value ?? 0) == (p.value ?? 0).roundToDouble());

  @override
  Widget build(BuildContext context) {
    final maxValue = points.map((p) => p.value ?? 0).reduce(math.max);
    // Whole-number stats like set counts never get fractional labels.
    final interval = math.max(_niceStep(maxValue / 4), wholeSteps ? 1.0 : 0.0);
    final top = (maxValue / interval).ceil() * interval;
    final barWidth = points.length > 6 ? 14.0 : 28.0;
    return BarChart(
      duration: Duration.zero,
      BarChartData(
        maxY: top,
        minY: 0,
        borderData: FlBorderData(show: false),
        gridData: _grid(interval),
        titlesData: _titles(points, interval),
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => AppColors.navPill,
            getTooltipItem: (group, _, rod, _) => BarTooltipItem(
              '${points[group.x].label}\n${_compact(rod.toY)}',
              const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
        ),
        barGroups: [
          for (final (index, point) in points.indexed)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: point.value ?? 0,
                  width: barWidth,
                  color: AppColors.accent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(4),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  const _LineChart({required this.points});
  final List<ChartPoint> points;

  @override
  Widget build(BuildContext context) {
    // Slots with no measurement are skipped, so the line joins its neighbours.
    final spots = [
      for (final (index, point) in points.indexed)
        if (point.value != null) FlSpot(index.toDouble(), point.value!),
    ];
    final values = spots.map((s) => s.y);
    final low = values.reduce(math.min);
    final high = values.reduce(math.max);
    final spread = high == low ? math.max(1.0, high * 0.1) : high - low;
    final interval = _niceStep(spread / 3);
    final minY = math.max(
      0.0,
      ((low - interval / 2) / interval).floor() * interval,
    );
    final maxY = ((high + interval / 2) / interval).ceil() * interval;

    return LineChart(
      duration: Duration.zero,
      LineChartData(
        minX: 0,
        maxX: (points.length - 1).toDouble(),
        minY: minY,
        maxY: maxY,
        borderData: FlBorderData(show: false),
        gridData: _grid(interval),
        titlesData: _titles(points, interval),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.navPill,
            getTooltipItems: (touched) => [
              for (final spot in touched)
                LineTooltipItem(
                  '${points[spot.x.toInt()].label}\n${_compact(spot.y)}',
                  const TextStyle(color: AppColors.textPrimary, fontSize: 12),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            color: AppColors.accent,
            barWidth: 3,
            isCurved: false,
            dotData: const FlDotData(show: true),
          ),
        ],
      ),
    );
  }
}
