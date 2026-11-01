import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';

class RoutinesScreen extends ConsumerWidget {
  const RoutinesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider);
    return Scaffold(
      appBar: AppBar(
        leading: const MenuButton(),
        title: const Text('Routines'),
        actions: [
          PopupMenuButton<void>(
            tooltip: 'More',
            useRootNavigator: true,
            itemBuilder: (context) => [
              PopupMenuItem(
                onTap: () => context.push('/routine-editor'),
                child: const Text('New routine'),
              ),
            ],
          ),
        ],
      ),
      body: routines.when(
        loading: () => const SizedBox.shrink(),
        error: (error, _) => Center(child: Text('$error')),
        data: (items) {
          if (items.isEmpty) {
            return const EmptyState(
              icon: Icons.fitness_center,
              title: 'No routines yet',
              message: 'Use the menu at the top to create your first routine.',
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, listBottomPadding),
            itemCount: items.length,
            itemBuilder: (context, index) => GroupedTile(
              index: index,
              count: items.length,
              title: Text(items[index].name),
              trailing: _RoutineMenu(routine: items[index]),
              onTap: () => context.push('/routine/${items[index].id}'),
            ),
          );
        },
      ),
    );
  }
}

class _RoutineMenu extends ConsumerWidget {
  const _RoutineMenu({required this.routine});
  final Routine routine;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete ${routine.name}?',
      message: 'Past workouts from this routine stay in your log.',
      action: 'Delete',
      destructive: true,
    );
    if (ok) await ref.read(routineRepositoryProvider).delete(routine.id);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The tab has its own navigator below the shell's button and nav bar. A
    // menu opened there would sit underneath them and lose taps to the button.
    return PopupMenuButton<void>(
      tooltip: 'Routine options',
      useRootNavigator: true,
      icon: const Icon(Icons.more_horiz, color: AppColors.accent),
      itemBuilder: (context) => [
        PopupMenuItem(
          onTap: () => context.push('/routine-editor?id=${routine.id}'),
          child: const Text('Edit'),
        ),
        PopupMenuItem(
          onTap: () => ref.read(routineRepositoryProvider).duplicate(routine.id),
          child: const Text('Duplicate'),
        ),
        PopupMenuItem(
          onTap: () => _delete(context, ref),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
