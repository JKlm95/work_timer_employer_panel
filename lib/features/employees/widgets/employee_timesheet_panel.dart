// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/entry_amount_breakdown.dart';
import '../../../core/utils/report_period.dart';
import '../../../core/utils/timesheet_entry_utils.dart';
import '../../../core/utils/timesheet_month_summary.dart';
import '../../../models/work_entry.dart';
import '../../../models/workspace.dart';
import '../../../services/firestore_service.dart';
import 'time_entry_edit_dialog.dart';

/// Month timesheet with filters, summary, and CRUD for `users/{employeeUid}/entries`.
class EmployeeTimesheetPanel extends StatefulWidget {
  const EmployeeTimesheetPanel({
    super.key,
    required this.firestore,
    required this.employerUid,
    required this.employeeUid,
    required this.workspaces,
  });

  final FirestoreService firestore;
  final String employerUid;
  final String employeeUid;
  final List<Workspace> workspaces;

  @override
  State<EmployeeTimesheetPanel> createState() => _EmployeeTimesheetPanelState();
}

class _EmployeeTimesheetPanelState extends State<EmployeeTimesheetPanel> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _workspaceFilter;
  String _entryTypeFilter = 'all';
  String _billableFilter = 'all';
  bool _showDeleted = false;
  final _searchCtrl = TextEditingController();
  TimesheetSort _sort = TimesheetSort.newestFirst;
  List<WorkEntry>? _lastGoodEntries;

  ReportPeriod get _period => monthContaining(_month);

  Map<String, Workspace> get _wsMap => {
    for (final w in widget.workspaces) w.id: w,
  };

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _prevMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _month = DateTime(_month.year, _month.month + 1);
    });
  }

  Future<void> _confirmDelete(WorkEntry e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Remove time entry?'),
        content: const Text(
          'The entry will be hidden and marked deleted (soft delete). '
          'You can restore it while “Show deleted” is on.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await widget.firestore.softDeleteEmployeeEntry(
        employerUid: widget.employerUid,
        employeeUid: widget.employeeUid,
        entryId: e.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Entry removed.')));
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Delete failed: $err')));
      }
    }
  }

  Future<void> _restore(WorkEntry e) async {
    try {
      await widget.firestore.restoreEmployeeEntry(
        employerUid: widget.employerUid,
        employeeUid: widget.employeeUid,
        entryId: e.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Entry restored.')));
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Restore failed: $err')));
      }
    }
  }

  String _statusLabel(WorkEntry e) {
    if (e.isDeleted) return 'Deleted';
    if (e.editedAt != null) return 'Edited';
    if (e.end == null) return 'Open';
    return 'Active';
  }

  @override
  Widget build(BuildContext context) {
    final wsEmpty = widget.workspaces.isEmpty;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Timesheet',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (!wsEmpty)
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final ok = await showTimeEntryEditorDialog(
                        context: context,
                        firestore: widget.firestore,
                        employeeUid: widget.employeeUid,
                        workspaces: widget.workspaces,
                      );
                      if (!context.mounted) return;
                      if (ok) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Entry saved.')),
                        );
                      }
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Add entry'),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Employer can add and edit closed entries for this employee. Amount uses workspace hourly rate × duration × billing %.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            if (wsEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'This employee has no workspaces in this company scope — timesheet is unavailable.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else ...[
              _monthNav(context),
              const SizedBox(height: 12),
              _filters(context),
              const SizedBox(height: 12),
              StreamBuilder<List<WorkEntry>>(
                key: ValueKey(
                  '${_period.start.toIso8601String()}_${widget.employeeUid}',
                ),
                stream: widget.firestore.employeeEntriesForMonthStream(
                  widget.employeeUid,
                  _period,
                ),
                builder: (context, snap) {
                  if (snap.hasError) {
                    final fallback = _lastGoodEntries ?? const <WorkEntry>[];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Material(
                          color: Theme.of(
                            context,
                          ).colorScheme.errorContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Text(
                              'Could not load entries: ${snap.error}. '
                              '${fallback.isEmpty ? "" : "Showing last loaded data."}',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onErrorContainer,
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildBody(context, fallback, loading: false),
                      ],
                    );
                  }
                  if (!snap.hasData) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: CircularProgressIndicator(),
                      ),
                    );
                  }
                  _lastGoodEntries = snap.data;
                  return _buildBody(context, snap.data!, loading: false);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _monthNav(BuildContext context) {
    final label = DateFormat.yMMMM().format(_month);
    return Row(
      children: [
        IconButton(onPressed: _prevMonth, icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        IconButton(
          onPressed: _nextMonth,
          icon: const Icon(Icons.chevron_right),
        ),
      ],
    );
  }

  Widget _filters(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 520;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SizedBox(
              width: narrow ? double.infinity : 200,
              child: DropdownButtonFormField<String>(
                value: _workspaceFilter ?? 'all',
                decoration: const InputDecoration(
                  labelText: 'Workspace',
                  isDense: true,
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('All workspaces'),
                  ),
                  for (final w in widget.workspaces)
                    DropdownMenuItem(
                      value: w.id,
                      child: Text(w.name, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _workspaceFilter = v == 'all' ? null : v),
              ),
            ),
            SizedBox(
              width: narrow ? double.infinity : 160,
              child: DropdownButtonFormField<String>(
                value: _entryTypeFilter,
                decoration: const InputDecoration(
                  labelText: 'Entry type',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All types')),
                  DropdownMenuItem(value: 'work', child: Text('work')),
                  DropdownMenuItem(value: 'vacation', child: Text('vacation')),
                  DropdownMenuItem(
                    value: 'sickLeave',
                    child: Text('sickLeave'),
                  ),
                  DropdownMenuItem(
                    value: 'businessTrip',
                    child: Text('businessTrip'),
                  ),
                  DropdownMenuItem(value: 'other', child: Text('other')),
                ],
                onChanged: (v) =>
                    v != null ? setState(() => _entryTypeFilter = v) : null,
              ),
            ),
            SizedBox(
              width: narrow ? double.infinity : 160,
              child: DropdownButtonFormField<String>(
                value: _billableFilter,
                decoration: const InputDecoration(
                  labelText: 'Billable',
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All')),
                  DropdownMenuItem(value: 'billable', child: Text('Billable')),
                  DropdownMenuItem(value: 'non', child: Text('Non-billable')),
                ],
                onChanged: (v) =>
                    v != null ? setState(() => _billableFilter = v) : null,
              ),
            ),
            FilterChip(
              label: const Text('Show deleted'),
              selected: _showDeleted,
              onSelected: (v) => setState(() => _showDeleted = v),
            ),
            SizedBox(
              width: narrow ? double.infinity : 220,
              child: TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'Search task / note',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
                onSubmitted: (_) => setState(() {}),
              ),
            ),
            IconButton(
              tooltip: 'Apply search',
              onPressed: () => setState(() {}),
              icon: const Icon(Icons.filter_alt_outlined),
            ),
            DropdownButtonFormField<TimesheetSort>(
              value: _sort,
              decoration: const InputDecoration(
                labelText: 'Sort',
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: TimesheetSort.newestFirst,
                  child: Text('Newest first'),
                ),
                DropdownMenuItem(
                  value: TimesheetSort.oldestFirst,
                  child: Text('Oldest first'),
                ),
                DropdownMenuItem(
                  value: TimesheetSort.durationDesc,
                  child: Text('Duration ↓'),
                ),
                DropdownMenuItem(
                  value: TimesheetSort.amountDesc,
                  child: Text('Amount ↓'),
                ),
              ],
              onChanged: (v) => v != null ? setState(() => _sort = v) : null,
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<WorkEntry> raw, {
    required bool loading,
  }) {
    bool? billableVal;
    if (_billableFilter == 'billable') billableVal = true;
    if (_billableFilter == 'non') billableVal = false;

    final filtered = filterTimesheetEntries(
      raw,
      workspaceId: _workspaceFilter,
      entryType: _entryTypeFilter,
      billableOnly: billableVal,
      showDeleted: _showDeleted,
      searchQuery: _searchCtrl.text,
    );

    final forTotals = filtered
        .where((e) => !e.isDeleted && e.end != null)
        .toList();
    final summary = TimesheetMonthSummary.compute(forTotals, _wsMap);

    final sorted = sortTimesheetEntries(
      filtered,
      _sort,
      amountOf: (e) =>
          EntryAmountResult.compute(e, _wsMap[e.workspaceId]).amountValue ?? 0,
    );

    if (raw.isEmpty && !loading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No entries in this month.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    if (sorted.isEmpty && !loading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'No entries match current filters.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summarySection(context, summary),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, c) {
            if (c.maxWidth < 900) {
              return _entryCards(context, sorted);
            }
            return _entryTable(context, sorted);
          },
        ),
      ],
    );
  }

  Widget _summarySection(BuildContext context, TimesheetMonthSummary s) {
    final fmtH = NumberFormat('#0.0');
    final h = s.totalDuration.inMinutes / 60.0;
    final bh = s.billableWorkDuration.inMinutes / 60.0;
    final nbh = s.nonBillableWorkDuration.inMinutes / 60.0;
    final money = s.amountByCurrency.entries
        .map((e) => '${e.key} ${e.value.toStringAsFixed(2)}')
        .join(' · ');
    final typeLines = s.durationByEntryTypeLabel.entries.map(
      (e) => '${e.key}: ${fmtH.format(e.value.inMinutes / 60.0)} h',
    );
    final pctLines = s.durationByBillingPercent.entries.map(
      (e) => '${e.key}%: ${fmtH.format(e.value.inMinutes / 60.0)} h',
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Month summary',
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            Chip(label: Text('Total: ${fmtH.format(h)} h')),
            Chip(label: Text('Billable work: ${fmtH.format(bh)} h')),
            Chip(label: Text('Non-bill. work: ${fmtH.format(nbh)} h')),
            Chip(label: Text('Estimated: ${money.isEmpty ? '—' : money}')),
          ],
        ),
        if (typeLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('By type', style: Theme.of(context).textTheme.labelLarge),
          ...typeLines.map(
            (t) => Text(t, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
        if (pctLines.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('By billing %', style: Theme.of(context).textTheme.labelLarge),
          ...pctLines.map(
            (t) => Text(t, style: Theme.of(context).textTheme.bodySmall),
          ),
        ],
      ],
    );
  }

  Widget _entryTable(BuildContext context, List<WorkEntry> rows) {
    final df = DateFormat.yMMMd();
    final tf = DateFormat.Hm();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Start')),
          DataColumn(label: Text('End')),
          DataColumn(label: Text('Duration')),
          DataColumn(label: Text('Project')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('%')),
          DataColumn(label: Text('Task')),
          DataColumn(label: Text('Note')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Actions')),
        ],
        rows: [
          for (final e in rows)
            DataRow(
              cells: [
                DataCell(Text(df.format(e.start))),
                DataCell(Text(tf.format(e.start))),
                DataCell(Text(e.end != null ? tf.format(e.end!) : '—')),
                DataCell(Text(_durStr(e))),
                DataCell(Text(_wsMap[e.workspaceId]?.name ?? e.workspaceId)),
                DataCell(Text(EntryAmountResult.entryTypeLabel(e.entryType))),
                DataCell(
                  Text('${(e.billingRatePercent ?? 100).toStringAsFixed(0)}%'),
                ),
                DataCell(
                  Text(
                    e.taskTitle ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(
                  Text(
                    e.note ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                DataCell(_amountCell(context, e)),
                DataCell(Text(_statusLabel(e))),
                DataCell(_actions(context, e)),
              ],
            ),
        ],
      ),
    );
  }

  Widget _entryCards(BuildContext context, List<WorkEntry> rows) {
    final df = DateFormat.yMMMd();
    final tf = DateFormat.Hm();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = rows[i];
        final ar = EntryAmountResult.compute(e, _wsMap[e.workspaceId]);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${df.format(e.start)} · ${tf.format(e.start)}–${e.end != null ? tf.format(e.end!) : "—"}',
                      ),
                    ),
                    Text(
                      _statusLabel(e),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ],
                ),
                Text(
                  _wsMap[e.workspaceId]?.name ?? e.workspaceId,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  '${_durStr(e)} · ${EntryAmountResult.entryTypeLabel(e.entryType)} · ${(e.billingRatePercent ?? 100).toStringAsFixed(0)}%',
                ),
                if (ar.formulaLine.isNotEmpty)
                  Text(
                    ar.formulaLine,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                Text(
                  'Amount: ${ar.displayAmount} ${ar.currency}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: _actions(context, e),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _durStr(WorkEntry e) {
    final d = e.duration;
    if (d == null) return '—';
    final h = d.inMinutes / 60.0;
    return '${h.toStringAsFixed(1)} h';
  }

  Widget _amountCell(BuildContext context, WorkEntry e) {
    final ar = EntryAmountResult.compute(e, _wsMap[e.workspaceId]);
    return Tooltip(
      message: ar.formulaLine.isEmpty
          ? (ar.skipReason == EntryAmountSkipReason.noRate
                ? 'No hourly rate on workspace'
                : '')
          : ar.formulaLine,
      child: Text(ar.displayAmount),
    );
  }

  Widget _actions(BuildContext context, WorkEntry e) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!e.isDeleted) ...[
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () async {
              final ok = await showTimeEntryEditorDialog(
                context: context,
                firestore: widget.firestore,
                employeeUid: widget.employeeUid,
                workspaces: widget.workspaces,
                existing: e,
              );
              if (!context.mounted) return;
              if (ok) {
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('Entry updated.')));
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: () => _confirmDelete(e),
          ),
        ] else
          TextButton(
            onPressed: () => _restore(e),
            child: const Text('Restore'),
          ),
      ],
    );
  }
}
