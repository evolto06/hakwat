import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../data/backup.dart';

const mockDataAsset = 'assets/dev/mock_data.json';

class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key});

  void _open(BuildContext context, String route) {
    Navigator.pop(context);
    context.push(route);
  }

  Future<void> _devAction(
    BuildContext context,
    WidgetRef ref,
    String doneMessage,
    Future<void> Function() action,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.pop(context);
    ref.read(restTimerProvider.notifier).stop();
    await action();
    messenger.showSnackBar(SnackBar(content: Text(doneMessage)));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                'hakwat',
                style: TextStyle(fontSize: 22, color: AppColors.accent),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.list_alt),
              title: const Text('Exercises'),
              onTap: () => _open(context, '/exercises'),
            ),
            ListTile(
              leading: const Icon(Icons.monitor_weight_outlined),
              title: const Text('Bodyweight'),
              onTap: () => _open(context, '/bodyweight'),
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              onTap: () => _open(context, '/settings'),
            ),
            ListTile(
              leading: const Icon(Icons.import_export),
              title: const Text('Export and restore'),
              onTap: () => _open(context, '/backup'),
            ),
            if (kDebugMode) ...[
              const Divider(),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text(
                  'Dev tools',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.dataset_outlined),
                title: const Text('Load mock data'),
                onTap: () => _devAction(
                  context,
                  ref,
                  'Mock data loaded',
                  () async {
                    final source = await rootBundle.loadString(mockDataAsset);
                    await replaceAllData(
                      ref.read(databaseProvider),
                      parseBackup(source),
                    );
                  },
                ),
              ),
              ListTile(
                leading: const Icon(Icons.delete_sweep_outlined),
                title: const Text('Clear all data'),
                onTap: () => _devAction(
                  context,
                  ref,
                  'All data cleared',
                  () => ref.read(databaseProvider).resetToFreshInstall(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
