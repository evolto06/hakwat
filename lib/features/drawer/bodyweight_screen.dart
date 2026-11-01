import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/format.dart';
import '../../core/widgets.dart';
import '../../data/database.dart';

class BodyweightScreen extends ConsumerWidget {
  const BodyweightScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entries = ref.watch(bodyweightProvider).value ?? const [];
    final unit = ref.watch(settingsProvider).unit;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bodyweight'),
        actions: [
          IconButton(
            icon: const Icon(Icons.show_chart),
            tooltip: 'Chart',
            onPressed: () => context.push('/stat/bodyweight'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add entry',
        onPressed: () => _showEntryDialog(context),
        child: const Icon(Icons.add),
      ),
      body: entries.isEmpty
          ? const EmptyState(
              icon: Icons.monitor_weight_outlined,
              title: 'No entries yet',
              message: 'Tap + to log your bodyweight.',
            )
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, listBottomPadding),
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return GroupedTile(
                  index: index,
                  count: entries.length,
                  title: Text(
                    DateFormat.yMMMEd().format(parseDayKey(entry.date)),
                  ),
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: Text(
                      '${formatWeight(entry.weightKg, unit)} ${unit.label}',
                    ),
                  ),
                  onTap: () => _showEntryDialog(context, existing: entry),
                );
              },
            ),
    );
  }

  Future<void> _showEntryDialog(
    BuildContext context, {
    BodyweightEntry? existing,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => _EntryDialog(existing: existing),
    );
  }
}

class _EntryDialog extends ConsumerStatefulWidget {
  const _EntryDialog({this.existing});
  final BodyweightEntry? existing;

  @override
  ConsumerState<_EntryDialog> createState() => _EntryDialogState();
}

class _EntryDialogState extends ConsumerState<_EntryDialog> {
  late DateTime _day = widget.existing == null
      ? DateTime.now()
      : parseDayKey(widget.existing!.date);
  late final _weight = TextEditingController(
    text: widget.existing == null
        ? ''
        : formatWeight(
            widget.existing!.weightKg,
            ref.read(settingsProvider).unit,
          ),
  );
  String? _error;

  @override
  void dispose() {
    _weight.dispose();
    super.dispose();
  }

  Future<void> _pickDay() async {
    final day = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (day != null) setState(() => _day = day);
  }

  Future<void> _save() async {
    final value = double.tryParse(_weight.text.trim().replaceAll(',', '.'));
    if (value == null || value <= 0) {
      setState(() => _error = 'Enter a weight');
      return;
    }
    final repo = ref.read(bodyweightRepositoryProvider);
    final unit = ref.read(settingsProvider).unit;
    final existing = widget.existing;
    // Moving an entry to another day removes the one on its old day.
    if (existing != null && existing.date != formatDayKey(_day)) {
      await repo.delete(existing.id);
    }
    await repo.save(_day, unit.toKg(value));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await ref.read(bodyweightRepositoryProvider).delete(widget.existing!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final unit = ref.watch(settingsProvider).unit;
    return AlertDialog(
      title: Text(widget.existing == null ? 'Add entry' : 'Edit entry'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            icon: const Icon(Icons.calendar_today, size: 18),
            label: Text(DateFormat.yMMMEd().format(_day)),
            onPressed: _pickDay,
          ),
          TextField(
            controller: _weight,
            autofocus: widget.existing == null,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: 'Weight',
              suffixText: unit.label,
              errorText: _error,
            ),
          ),
        ],
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            onPressed: _delete,
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}
