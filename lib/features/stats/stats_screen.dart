import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme.dart';
import '../../core/widgets.dart';
import '../../data/seed_exercises.dart';
import '../../data/stats.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  static const _chevron = Padding(
    padding: EdgeInsets.only(right: 8),
    child: Icon(Icons.chevron_right, color: AppColors.accent),
  );

  @override
  Widget build(BuildContext context) {
    const overall = OverallStat.values;
    return Scaffold(
      appBar: AppBar(leading: const MenuButton(), title: const Text('Statistics')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: listBottomPadding),
        children: [
          const SectionHeader('Overall Statistics'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final (index, stat) in overall.indexed)
                  GroupedTile(
                    index: index,
                    count: overall.length,
                    title: Text(stat.label),
                    trailing: _chevron,
                    onTap: () => context.push('/stat/${stat.name}'),
                  ),
              ],
            ),
          ),
          const SectionHeader('Category Statistics'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (final (index, category) in categories.indexed)
                  GroupedTile(
                    index: index,
                    count: categories.length,
                    title: Text(category),
                    trailing: _chevron,
                    onTap: () => context.push('/category/$category'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
