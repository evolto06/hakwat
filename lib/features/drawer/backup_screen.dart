import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/widgets.dart';
import '../../data/backup.dart';

class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final json = await buildExportJson(ref.read(databaseProvider));
    final directory = await getTemporaryDirectory();
    final day = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final file = File('${directory.path}/hakwat-export-$day.json');
    await file.writeAsString(json, flush: true);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: 'application/json')]),
    );
  }

  Future<void> _restore() async {
    final picked = await FilePicker.pickFiles();
    final path = picked.isEmpty ? null : picked.first.path;
    if (path == null) return;

    final ParsedBackup backup;
    try {
      backup = parseBackup(await File(path).readAsString());
    } on BackupFormatException catch (error) {
      _showFailure(error.message);
      return;
    } on FileSystemException {
      _showFailure('This file could not be read as text.');
      return;
    } on FormatException {
      _showFailure('This file could not be read as text.');
      return;
    }
    if (!mounted) return;

    final exported = backup.exportedAt;
    final ok = await confirm(
      context,
      title: 'Replace all data?',
      message:
          '${exported == null ? 'This file' : 'The export from ${DateFormat.yMMMd().format(exported.toLocal())}'} '
          'has ${backup.workouts.length} workouts and '
          '${backup.routines.length} routines. Everything now in the app will '
          'be replaced.',
      action: 'Replace',
      destructive: true,
    );
    if (!ok) return;

    ref.read(restTimerProvider.notifier).stop();
    await replaceAllData(ref.read(databaseProvider), backup);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Data restored')));
    }
  }

  void _showFailure(String message) {
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Nothing was changed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export and restore')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GroupedTile(
            index: 0,
            count: 2,
            title: const Text('Export'),
            subtitle: const Text(
              'Save everything to a JSON file you can share',
            ),
            trailing: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.ios_share, color: AppColors.accent),
            ),
            onTap: _busy ? null : () => _run(_export),
          ),
          GroupedTile(
            index: 1,
            count: 2,
            title: const Text('Restore'),
            subtitle: const Text('Replace all data from an export file'),
            trailing: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.restore, color: AppColors.accent),
            ),
            onTap: _busy ? null : () => _run(_restore),
          ),
        ],
      ),
    );
  }
}
