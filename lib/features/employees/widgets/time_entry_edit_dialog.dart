// ignore_for_file: deprecated_member_use

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/time_entry_validation.dart';
import '../../../models/work_entry.dart';
import '../../../models/workspace.dart';
import '../../../services/firestore_service.dart';

/// Create or edit a closed time entry (employer panel).
Future<bool> showTimeEntryEditorDialog({
  required BuildContext context,
  required FirestoreService firestore,
  required String employeeUid,
  required List<Workspace> workspaces,
  WorkEntry? existing,
}) async {
  final r = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _TimeEntryEditorDialog(
      firestore: firestore,
      employeeUid: employeeUid,
      workspaces: workspaces,
      existing: existing,
    ),
  );
  return r ?? false;
}

class _TimeEntryEditorDialog extends StatefulWidget {
  const _TimeEntryEditorDialog({
    required this.firestore,
    required this.employeeUid,
    required this.workspaces,
    this.existing,
  });

  final FirestoreService firestore;
  final String employeeUid;
  final List<Workspace> workspaces;
  final WorkEntry? existing;

  @override
  State<_TimeEntryEditorDialog> createState() => _TimeEntryEditorDialogState();
}

class _TimeEntryEditorDialogState extends State<_TimeEntryEditorDialog> {
  final _formKey = GlobalKey<FormState>();
  late String? _workspaceId;
  late DateTime _day;
  late TimeOfDay _startT;
  late TimeOfDay _endT;
  late String _entryType;
  late int _billingPct;
  late bool _billable;
  final _taskTitle = TextEditingController();
  final _note = TextEditingController();
  final _modeCtrl = TextEditingController(text: 'employer_panel');
  bool _saving = false;

  static const _types = [
    'work',
    'vacation',
    'sickLeave',
    'businessTrip',
    'other',
  ];

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _workspaceId = e.workspaceId.isEmpty ? null : e.workspaceId;
      _day = DateTime(e.start.year, e.start.month, e.start.day);
      _startT = TimeOfDay.fromDateTime(e.start);
      _endT = TimeOfDay.fromDateTime(
        e.end ?? e.start.add(const Duration(hours: 1)),
      );
      _entryType = e.entryType ?? 'work';
      _billingPct = (e.billingRatePercent ?? 100).round();
      if (!kAllowedBillingPercents.contains(_billingPct)) {
        _billingPct = 100;
      }
      _billable = e.effectiveBillable;
      _taskTitle.text = e.taskTitle ?? '';
      _note.text = e.note ?? '';
      _modeCtrl.text = e.mode.isEmpty ? 'employer_panel' : e.mode;
    } else {
      _workspaceId = widget.workspaces.isEmpty
          ? null
          : widget.workspaces.first.id;
      final n = DateTime.now();
      _day = DateTime(n.year, n.month, n.day);
      _startT = const TimeOfDay(hour: 9, minute: 0);
      _endT = const TimeOfDay(hour: 17, minute: 0);
      _entryType = 'work';
      _billingPct = 100;
      _billable = true;
    }
  }

  @override
  void dispose() {
    _taskTitle.dispose();
    _note.dispose();
    _modeCtrl.dispose();
    super.dispose();
  }

  DateTime _combine(DateTime day, TimeOfDay t) {
    return DateTime(day.year, day.month, day.day, t.hour, t.minute);
  }

  Future<void> _pickDay() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (d != null) setState(() => _day = d);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_workspaceId == null || _workspaceId!.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Choose a workspace.')));
      return;
    }
    final employer = FirebaseAuth.instance.currentUser?.uid;
    if (employer == null) return;

    final start = _combine(_day, _startT);
    final end = _combine(_day, _endT);
    try {
      assertClosedInterval(start, end);
      assertValidBillingPercent(_billingPct);
    } on TimeEntryValidationException catch (err) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$err')));
      return;
    }

    setState(() => _saving = true);
    try {
      final tt = _taskTitle.text.trim();
      final nt = _note.text.trim();
      final mode = _modeCtrl.text.trim().isEmpty
          ? 'employer_panel'
          : _modeCtrl.text.trim();

      if (widget.existing == null) {
        final data = <String, dynamic>{
          'workspaceId': _workspaceId!.trim(),
          'start': Timestamp.fromDate(start),
          'end': Timestamp.fromDate(end),
          'mode': mode,
          'updatedAt': FieldValue.serverTimestamp(),
          'isDeleted': false,
          'isBillable': _billable,
          'entryType': _entryType,
          'billingRatePercent': _billingPct,
          'createdBy': employer,
          'createdVia': 'employer_panel',
        };
        if (tt.isNotEmpty) data['taskTitle'] = tt;
        if (nt.isNotEmpty) data['note'] = nt;
        await widget.firestore.createEmployeeEntry(
          employerUid: employer,
          employeeUid: widget.employeeUid,
          data: data,
        );
      } else {
        final data = <String, dynamic>{
          'workspaceId': _workspaceId!.trim(),
          'start': Timestamp.fromDate(start),
          'end': Timestamp.fromDate(end),
          'mode': mode,
          'updatedAt': FieldValue.serverTimestamp(),
          'isDeleted': false,
          'isBillable': _billable,
          'entryType': _entryType,
          'billingRatePercent': _billingPct,
          'editedAt': FieldValue.serverTimestamp(),
          'editedBy': employer,
        };
        if (tt.isNotEmpty) {
          data['taskTitle'] = tt;
        } else {
          data['taskTitle'] = FieldValue.delete();
        }
        if (nt.isNotEmpty) {
          data['note'] = nt;
        } else {
          data['note'] = FieldValue.delete();
        }
        await widget.firestore.updateEmployeeEntry(
          employeeUid: widget.employeeUid,
          entryId: widget.existing!.id,
          data: data,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actionsAlignment: MainAxisAlignment.end,
      title: Text(isEdit ? 'Edit time entry' : 'Add time entry'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Workspace & time',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _workspaceId,
                  decoration: const InputDecoration(labelText: 'Workspace'),
                  items: [
                    for (final w in widget.workspaces)
                      DropdownMenuItem(value: w.id, child: Text(w.name)),
                  ],
                  onChanged: (v) => setState(() => _workspaceId = v),
                  validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Date'),
                  subtitle: Text(
                    MaterialLocalizations.of(context).formatFullDate(_day),
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: _pickDay,
                  ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<TimeOfDay>(
                        value: _startT,
                        decoration: const InputDecoration(labelText: 'Start'),
                        items: _timeMenu(),
                        onChanged: (v) =>
                            v != null ? setState(() => _startT = v) : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<TimeOfDay>(
                        value: _endT,
                        decoration: const InputDecoration(labelText: 'End'),
                        items: _timeMenu(),
                        onChanged: (v) =>
                            v != null ? setState(() => _endT = v) : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Classification',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: _entryType,
                  decoration: const InputDecoration(labelText: 'Entry type'),
                  items: [
                    for (final t in _types)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) =>
                      v != null ? setState(() => _entryType = v) : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  value: _billingPct,
                  decoration: const InputDecoration(
                    labelText: 'Billing rate %',
                  ),
                  items: [
                    for (final p in kAllowedBillingPercents)
                      DropdownMenuItem(value: p, child: Text('$p%')),
                  ],
                  onChanged: (v) =>
                      v != null ? setState(() => _billingPct = v) : null,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Billable'),
                  value: _billable,
                  onChanged: (v) => setState(() => _billable = v),
                ),
                TextFormField(
                  controller: _taskTitle,
                  decoration: const InputDecoration(
                    labelText: 'Task title (optional)',
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _note,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                Text(
                  'Technical',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _modeCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Mode',
                    helperText: 'Default: employer_panel',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  List<DropdownMenuItem<TimeOfDay>> _timeMenu() {
    final items = <DropdownMenuItem<TimeOfDay>>[];
    for (var h = 0; h < 24; h++) {
      for (final m in [0, 15, 30, 45]) {
        final t = TimeOfDay(hour: h, minute: m);
        items.add(DropdownMenuItem(value: t, child: Text(t.format(context))));
      }
    }
    return items;
  }
}
