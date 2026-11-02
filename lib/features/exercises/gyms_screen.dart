import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';
import '../../data/library_repositories.dart';

/// Asks for a name and creates a gym. Returns its ID, or null if cancelled or
/// the name is taken, which is reported through a snack bar.
Future<String?> createGym(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final name = await promptForText(context, title: 'New gym', action: 'Add');
  if (name == null) return null;
  try {
    return await ref.read(gymRepositoryProvider).create(name);
  } on DuplicateGymName {
    messenger.showSnackBar(
      SnackBar(content: Text('A gym named $name already exists.')),
    );
    return null;
  }
}

class GymsScreen extends ConsumerWidget {
  const GymsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gyms = ref.watch(gymsProvider).value ?? const <Gym>[];
    final exercises = ref.watch(exercisesProvider).value ?? const <Exercise>[];

    return Scaffold(
      appBar: AppBar(title: const Text('Gyms')),
      floatingActionButton: FloatingActionButton(
        tooltip: 'New gym',
        onPressed: () => createGym(context, ref),
        child: const Icon(Icons.add),
      ),
      body: gyms.isEmpty
          ? const EmptyState(
              icon: Icons.location_on_outlined,
              title: 'No gyms yet',
              message: 'Add a gym to keep track of the machines that are only there.',
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, listBottomPadding),
              children: [
                for (final (index, gym) in gyms.indexed)
                  GroupedTile(
                    index: index,
                    count: gyms.length,
                    title: Text(gym.name),
                    subtitle: Text(
                      _machineCount(
                        exercises.where((e) => e.gymId == gym.id).length,
                      ),
                    ),
                    trailing: _GymMenu(gym: gym),
                  ),
              ],
            ),
    );
  }

  String _machineCount(int count) =>
      '$count ${count == 1 ? 'machine' : 'machines'}';
}

class _GymMenu extends ConsumerWidget {
  const _GymMenu({required this.gym});
  final Gym gym;

  void _show(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _rename(BuildContext context, WidgetRef ref) async {
    final name = await promptForText(
      context,
      title: 'Gym name',
      initial: gym.name,
    );
    if (name == null) return;
    try {
      await ref.read(gymRepositoryProvider).rename(gym.id, name);
    } on DuplicateGymName {
      if (context.mounted) {
        _show(context, 'A gym named $name already exists.');
      }
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final ok = await confirm(
      context,
      title: 'Delete ${gym.name}?',
      action: 'Delete',
      destructive: true,
    );
    if (!ok) return;
    try {
      await ref.read(gymRepositoryProvider).delete(gym.id);
    } on GymInUse catch (error) {
      if (context.mounted) {
        final count = error.exerciseCount;
        _show(
          context,
          '${gym.name} still has $count '
          '${count == 1 ? 'machine' : 'machines'}, including archived ones. '
          'Move them to another gym first.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<void>(
      tooltip: 'Gym options',
      icon: const Icon(Icons.more_horiz, color: AppColors.accent),
      itemBuilder: (_) => [
        PopupMenuItem(
          onTap: () => _rename(context, ref),
          child: const Text('Rename'),
        ),
        PopupMenuItem(
          onTap: () => _delete(context, ref),
          child: const Text('Delete'),
        ),
      ],
    );
  }
}
