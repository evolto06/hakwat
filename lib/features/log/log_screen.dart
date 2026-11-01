import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/workout_repository.dart';

class _Month {
  _Month(this.first);
  final DateTime first;
  final List<WorkoutSummary> workouts = [];
}

List<_Month> _groupByMonth(List<WorkoutSummary> workouts) {
  final months = <_Month>[];
  for (final summary in workouts) {
    final local = summary.workout.startedAt.toLocal();
    if (months.isEmpty ||
        months.last.first.year != local.year ||
        months.last.first.month != local.month) {
      months.add(_Month(DateTime(local.year, local.month)));
    }
    months.last.workouts.add(summary);
  }
  return months;
}

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  final _listKey = GlobalKey();
  final _monthKeys = <DateTime, GlobalKey>{};
  final _monthInView = ValueNotifier<DateTime?>(null);
  List<_Month> _months = const [];

  @override
  void dispose() {
    _monthInView.dispose();
    super.dispose();
  }

  /// The month in view is the last section whose header has reached the top of
  /// the list. Only sections near the screen are built, and those are the only
  /// ones that can qualify.
  void _updateMonthInView() {
    final listBox = _listKey.currentContext?.findRenderObject() as RenderBox?;
    if (listBox == null || !listBox.attached) return;
    final top = listBox.localToGlobal(Offset.zero).dy;

    DateTime? current;
    for (final month in _months) {
      final context = _monthKeys[month.first]?.currentContext;
      final box = context?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      if (box.localToGlobal(Offset.zero).dy <= top + 1) current = month.first;
    }
    _monthInView.value = current ?? _firstBuiltMonth();
  }

  /// Scroll notifications arrive before layout, so header positions are only
  /// current once the frame is done.
  void _updateAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateMonthInView();
    });
  }

  DateTime? _firstBuiltMonth() {
    for (final month in _months) {
      if (_monthKeys[month.first]?.currentContext != null) return month.first;
    }
    return _months.isEmpty ? null : _months.first.first;
  }

  @override
  Widget build(BuildContext context) {
    final log = ref.watch(logProvider);
    _months = _groupByMonth(log.value ?? const []);
    _updateAfterFrame();

    return Scaffold(
      appBar: AppBar(
        leading: const MenuButton(),
        title: ValueListenableBuilder(
          valueListenable: _monthInView,
          builder: (context, month, _) =>
              Text(month == null ? 'Log' : DateFormat.MMMM().format(month)),
        ),
      ),
      body: switch (log) {
        AsyncValue(hasValue: false, hasError: false) => const SizedBox.shrink(),
        AsyncError(:final error) => Center(child: Text('$error')),
        _ when _months.isEmpty => const EmptyState(
          icon: Icons.history,
          title: 'No workouts yet',
          message: 'Workouts you log will show up here.',
        ),
        _ => NotificationListener<ScrollNotification>(
          onNotification: (_) {
            _updateAfterFrame();
            return false;
          },
          child: ListView.builder(
            key: _listKey,
            padding: const EdgeInsets.only(bottom: listBottomPadding),
            itemCount: _months.length,
            itemBuilder: (context, index) {
              final month = _months[index];
              return _MonthSection(
                key: _monthKeys.putIfAbsent(month.first, GlobalKey.new),
                month: month,
              );
            },
          ),
        ),
      },
    );
  }
}

class _MonthSection extends StatelessWidget {
  const _MonthSection({super.key, required this.month});
  final _Month month;

  @override
  Widget build(BuildContext context) {
    final count = month.workouts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(68, 20, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  DateFormat.yMMMM().format(month.first),
                  style: _headerStyle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$count ${count == 1 ? 'workout' : 'workouts'}',
                style: _headerStyle,
              ),
            ],
          ),
        ),
        for (final summary in month.workouts) _WorkoutCard(summary: summary),
      ],
    );
  }

  static const _headerStyle = TextStyle(
    color: AppColors.textSecondary,
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
  );
}

class _WorkoutCard extends StatelessWidget {
  const _WorkoutCard({required this.summary});
  final WorkoutSummary summary;

  @override
  Widget build(BuildContext context) {
    final workout = summary.workout;
    final date = workout.startedAt.toLocal();
    final duration = summary.duration;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 0, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 52, child: _DateRail(date: date)),
          Expanded(
            child: Material(
              color: AppColors.card,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => context.push(
                  summary.isOpen
                      ? '/workout/${workout.id}'
                      : '/history/${workout.id}',
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              workout.nameSnapshot,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          if (duration != null)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                formatDuration(duration),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (summary.lines.isEmpty)
                        const Text('No sets completed', style: _lineStyle)
                      else
                        for (final line in summary.lines)
                          Text(
                            '${line.completedSets}x ${line.exerciseName}',
                            style: _lineStyle,
                          ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static const _lineStyle = TextStyle(
    fontSize: 14,
    height: 1.36,
    letterSpacing: 0.25,
    color: AppColors.textSecondary,
  );
}

class _DateRail extends StatelessWidget {
  const _DateRail({required this.date});
  final DateTime date;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 12, color: AppColors.textSecondary);
    return Column(
      children: [
        const SizedBox(height: 2),
        Text(DateFormat.E().format(date).toUpperCase(), style: small),
        Text(
          '${date.day}',
          style: const TextStyle(fontSize: 22, color: AppColors.textPrimary),
        ),
        Text(DateFormat.MMM().format(date).toUpperCase(), style: small),
      ],
    );
  }
}
