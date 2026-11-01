import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../data/library_repositories.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  static const _restOptions = [0, 30, 45, 60, 90, 120, 150, 180, 240, 300];

  String _restLabel(int seconds) {
    if (seconds == 0) return 'Off';
    return seconds < 60 ? '$seconds s' : formatClock(Duration(seconds: seconds));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final repo = ref.read(settingsRepositoryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Weight unit'),
            subtitle: const Text('Weights are stored in kg either way'),
            trailing: SegmentedButton<WeightUnit>(
              showSelectedIcon: false,
              segments: [
                for (final unit in WeightUnit.values)
                  ButtonSegment(value: unit, label: Text(unit.label)),
              ],
              selected: {settings.unit},
              onSelectionChanged: (value) =>
                  repo.set(AppSettings.unitKey, value.single.name),
            ),
          ),
          ListTile(
            title: const Text('Rest timer'),
            subtitle: const Text('Starts when you complete a set'),
            trailing: DropdownButton<int>(
              value: _restOptions.contains(settings.restSeconds)
                  ? settings.restSeconds
                  : 90,
              underline: const SizedBox.shrink(),
              dropdownColor: AppColors.navPill,
              items: [
                for (final seconds in _restOptions)
                  DropdownMenuItem(
                    value: seconds,
                    child: Text(_restLabel(seconds)),
                  ),
              ],
              onChanged: (value) =>
                  repo.set(AppSettings.restSecondsKey, '$value'),
            ),
          ),
          SwitchListTile(
            title: const Text('Rest alert'),
            subtitle: const Text('Notifies you when rest ends, even when locked'),
            value: settings.restAlert,
            onChanged: (value) async {
              await repo.set(AppSettings.restAlertKey, '$value');
              if (value) {
                await ref.read(restAlertsProvider).requestPermission();
              }
            },
          ),
          SwitchListTile(
            title: const Text('Keep screen awake'),
            subtitle: const Text('While a workout is open on screen'),
            value: settings.keepAwake,
            onChanged: (value) => repo.set(AppSettings.keepAwakeKey, '$value'),
          ),
        ],
      ),
    );
  }
}
