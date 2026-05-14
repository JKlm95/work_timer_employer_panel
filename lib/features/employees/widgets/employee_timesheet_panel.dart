// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/debug/employer_entries_debug_config.dart';
import '../../../core/theme/app_layout.dart';
import '../../../core/utils/employer_workspace_lookup.dart';
import '../../../core/utils/entry_amount_breakdown.dart';
import '../../../core/utils/report_period.dart';
import '../../../core/utils/timesheet_entry_utils.dart';
import '../../../core/utils/timesheet_month_summary.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_pulse_loading.dart';
import '../../../models/work_entry.dart';
import '../../../models/workspace.dart';
import '../../../services/firestore_service.dart';
import 'time_entry_edit_dialog.dart';
import 'timesheet_entry_badges.dart';

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
      builder: (c) {
        final scheme = Theme.of(c).colorScheme;
        return AlertDialog(
          icon: Icon(Icons.delete_outline_rounded, color: scheme.error),
          title: const Text('Remove time entry?'),
          content: const Text(
            'The entry will be hidden and marked deleted (soft delete). '
            'You can restore it while “Show deleted” is on.',
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actionsAlignment: MainAxisAlignment.end,
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.error,
                foregroundColor: scheme.onError,
              ),
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
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
        padding: const EdgeInsets.all(AppLayout.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'Timesheet',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
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
            const SizedBox(height: 6),
            Text(
              'Employer can add and edit closed entries for this employee. Amount uses workspace hourly rate × duration × billing %.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            if (wsEmpty)
              AppEmptyState(
                icon: Icons.workspaces_outlined,
                title: 'No shared workspaces',
                subtitle: 'No shared workspaces available for this employee.',
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
                  widget.employerUid,
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
                    return const Padding(
                      padding: EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 8,
                      ),
                      child: AppPulseLoading(rows: 6),
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
    final scheme = Theme.of(context).colorScheme;
    final label = DateFormat.yMMMM().format(_month);
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(AppLayout.radiusMd),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Previous month',
              onPressed: _prevMonth,
              icon: const Icon(Icons.chevron_left),
            ),
            Expanded(
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Next month',
              onPressed: _nextMonth,
              icon: const Icon(Icons.chevron_right),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filters(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final narrow = c.maxWidth < 520;
        final scheme = Theme.of(context).colorScheme;
        return Material(
          color: scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppLayout.radiusMd),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.65),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
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
                    onChanged: (v) => setState(
                      () => _workspaceFilter = v == 'all' ? null : v,
                    ),
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
                      DropdownMenuItem(
                        value: 'vacation',
                        child: Text('vacation'),
                      ),
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
                      DropdownMenuItem(
                        value: 'billable',
                        child: Text('Billable'),
                      ),
                      DropdownMenuItem(
                        value: 'non',
                        child: Text('Non-billable'),
                      ),
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
                  onChanged: (v) =>
                      v != null ? setState(() => _sort = v) : null,
                ),
              ],
            ),
          ),
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
    final wsLookup = buildWorkspaceLookupByScopedKey(
      widget.employeeUid,
      widget.workspaces,
    );
    Workspace? workspaceFor(WorkEntry e) =>
        workspaceForEmployerEntry(wsLookup, widget.employeeUid, e.workspaceId);

    if (EmployerEntriesDebugConfig.tracePipelineForEmployee(widget.employeeUid)) {
      final fid = EmployerEntriesDebugConfig.focusEntryId?.trim();
      debugPrint(
        '[Timesheet/_buildBody TRACE] employer=${widget.employerUid} '
        'employee=${widget.employeeUid} '
        'monthStart=${_period.start.toIso8601String()} '
        'monthEnd=${_period.endInclusive.toIso8601String()} '
        'raw=${raw.length} filtered=${filtered.length} '
        'workspaceFilter=${_workspaceFilter ?? '(none)'} entryType=$_entryTypeFilter '
        'billable=$_billableFilter showDeleted=$_showDeleted '
        'searchLen=${_searchCtrl.text.trim().length}',
      );
      if (fid != null && fid.isNotEmpty) {
        WorkEntry? focus;
        for (final e in raw) {
          if (e.id == fid) {
            focus = e;
            break;
          }
        }
        if (focus == null) {
          debugPrint(
            '[Timesheet/_buildBody TRACE] FOCUS entryId=$fid NOT in raw stream '
            '(${raw.length} rows)',
          );
        } else {
          debugPrint(
            '[Timesheet/_buildBody TRACE] FOCUS raw ${_period.start.toIso8601String()} '
            'id=${focus.id} workspaceId=${focus.workspaceId.trim()} '
            'start=${focus.start.toIso8601String()} '
            'end=${focus.end?.toIso8601String() ?? 'null'} '
            'isDeleted=${focus.isDeleted}',
          );
          final reject = explainTimesheetFilterReject(
            focus,
            workspaceId: _workspaceFilter,
            entryType: _entryTypeFilter,
            billableOnly: billableVal,
            showDeleted: _showDeleted,
            searchQuery: _searchCtrl.text,
          );
          if (reject != null) {
            debugPrint('[Timesheet/_buildBody TRACE] $reject');
          } else {
            debugPrint(
              '[Timesheet/_buildBody TRACE] filterTimesheetEntries: PASS',
            );
          }
          final inFiltered = filtered.any((e) => e.id == fid);
          debugPrint(
            '[Timesheet/_buildBody TRACE] FOCUS inFiltered=$inFiltered',
          );
          final ws = workspaceFor(focus);
          debugPrint(
            '[Timesheet/_buildBody TRACE] workspaceForEmployerEntry='
            '${ws == null ? 'MISS' : 'HIT'} '
            'lookupKey=${employerWorkspaceLookupKey(widget.employeeUid, focus.workspaceId)}',
          );
          final inForTotals = forTotals.any((e) => e.id == fid);
          final dur = focus.duration;
          debugPrint(
            '[Timesheet/_buildBody TRACE] TimesheetMonthSummary.forTotals: '
            'FOCUS inForTotals=$inForTotals durationNull=${dur == null} '
            '(compute skips isDeleted or duration==null in aggregation loop; '
            'brak osobnej funkcji countsInTimeAggregates — patrz '
            'TimesheetMonthSummary.compute)',
          );
        }
      }
    }

    final summary = TimesheetMonthSummary.compute(
      forTotals,
      wsLookup,
      widget.employeeUid,
    );

    final sorted = sortTimesheetEntries(
      filtered,
      _sort,
      amountOf: (e) =>
          EntryAmountResult.compute(e, workspaceFor(e)).amountValue ?? 0,
    );

    if (kDebugMode && raw.isNotEmpty && filtered.isEmpty && !loading) {
      debugPrint(
        '[Timesheet/filter] employer=${widget.employerUid} '
        'employee=${widget.employeeUid} month=${_period.start.toIso8601String()}..'
        '${_period.endInclusive.toIso8601String()} raw=${raw.length} '
        'skippedReason=all rows removed by workspace/type/billable/deleted/search filters',
      );
    }

    if (raw.isEmpty && !loading) {
      return AppEmptyState(
        icon: Icons.event_busy_outlined,
        title: 'No entries in this month',
        subtitle:
            'When this employee logs time for this month, it will show up here.',
      );
    }

    if (sorted.isEmpty && !loading) {
      return AppEmptyState(
        icon: Icons.filter_alt_off_outlined,
        title: 'No entries match current filters',
        subtitle:
            'Try clearing search or changing workspace, type, or billable filters.',
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
              return _entryCards(context, sorted, wsLookup);
            }
            return _entryTable(context, sorted, wsLookup);
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
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(
              avatar: const Icon(Icons.schedule, size: 18),
              label: Text('Total: ${fmtH.format(h)} h'),
            ),
            Chip(
              avatar: const Icon(Icons.trending_up, size: 18),
              label: Text('Billable work: ${fmtH.format(bh)} h'),
            ),
            Chip(
              avatar: const Icon(Icons.trending_flat, size: 18),
              label: Text('Non-bill. work: ${fmtH.format(nbh)} h'),
            ),
            Chip(
              avatar: const Icon(Icons.payments_outlined, size: 18),
              label: Text('Estimated: ${money.isEmpty ? '—' : money}'),
            ),
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

  Widget _entryTable(
    BuildContext context,
    List<WorkEntry> rows,
    Map<String, Workspace> wsLookup,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final df = DateFormat.yMMMd();
    final tf = DateFormat.Hm();
    final mono = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 920),
        child: DataTable(
          headingRowColor: WidgetStatePropertyAll(
            scheme.surfaceContainerHighest.withValues(alpha: 0.55),
          ),
          dataRowMinHeight: 52,
          dataRowMaxHeight: 96,
          columns: const [
            DataColumn(label: Text('Date')),
            DataColumn(label: Text('Start')),
            DataColumn(label: Text('End')),
            DataColumn(label: Text('Duration')),
            DataColumn(label: Text('Project')),
            DataColumn(label: Text('Tags')),
            DataColumn(label: Text('Task')),
            DataColumn(label: Text('Note')),
            DataColumn(numeric: true, label: Text('Amount')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (var i = 0; i < rows.length; i++)
              _dataRowForEntry(context, rows[i], i, df, tf, mono, wsLookup),
          ],
        ),
      ),
    );
  }

  DataRow _dataRowForEntry(
    BuildContext context,
    WorkEntry e,
    int index,
    DateFormat df,
    DateFormat tf,
    TextStyle? mono,
    Map<String, Workspace> wsLookup,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final wsName =
        workspaceForEmployerEntry(
          wsLookup,
          widget.employeeUid,
          e.workspaceId,
        )?.name ??
        e.workspaceId;
    final task = e.taskTitle ?? '';
    final note = e.note ?? '';
    return DataRow(
      color: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.hovered)) {
          return scheme.primary.withValues(alpha: 0.07);
        }
        if (index.isEven) {
          return scheme.surfaceContainerHighest.withValues(alpha: 0.4);
        }
        return null;
      }),
      cells: [
        DataCell(Text(df.format(e.start))),
        DataCell(Text(tf.format(e.start), style: mono)),
        DataCell(Text(e.end != null ? tf.format(e.end!) : '—', style: mono)),
        DataCell(
          Text(_durStr(e), style: mono?.copyWith(fontWeight: FontWeight.w600)),
        ),
        DataCell(
          Tooltip(
            message: wsName,
            child: Text(wsName, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ),
        DataCell(
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: TimesheetEntryBadges(entry: e, dense: true),
          ),
        ),
        DataCell(
          Tooltip(
            message: task.isEmpty ? '' : task,
            child: Text(
              task.isEmpty ? '—' : task,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(
          Tooltip(
            message: note.isEmpty ? '' : note,
            child: Text(
              note.isEmpty ? '—' : note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        DataCell(_amountCell(context, e, wsLookup)),
        DataCell(Text(_statusLabel(e))),
        DataCell(_actions(context, e)),
      ],
    );
  }

  Widget _entryCards(
    BuildContext context,
    List<WorkEntry> rows,
    Map<String, Workspace> wsLookup,
  ) {
    final df = DateFormat.yMMMd();
    final tf = DateFormat.Hm();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: rows.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final e = rows[i];
        final ar = EntryAmountResult.compute(
          e,
          workspaceForEmployerEntry(
            wsLookup,
            widget.employeeUid,
            e.workspaceId,
          ),
        );
        return Card(
          clipBehavior: Clip.antiAlias,
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${df.format(e.start)} · ${tf.format(e.start)}–${e.end != null ? tf.format(e.end!) : "—"}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text(
                      _statusLabel(e),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  workspaceForEmployerEntry(
                        wsLookup,
                        widget.employeeUid,
                        e.workspaceId,
                      )?.name ??
                      e.workspaceId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                TimesheetEntryBadges(entry: e),
                const SizedBox(height: 8),
                Text(
                  _durStr(e),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (ar.formulaLine.isNotEmpty)
                  Text(
                    ar.formulaLine,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                Text(
                  'Amount: ${ar.displayAmount} ${ar.currency}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
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

  Widget _amountCell(
    BuildContext context,
    WorkEntry e,
    Map<String, Workspace> wsLookup,
  ) {
    final ar = EntryAmountResult.compute(
      e,
      workspaceForEmployerEntry(wsLookup, widget.employeeUid, e.workspaceId),
    );
    final t = Theme.of(context);
    return Tooltip(
      message: ar.formulaLine.isEmpty
          ? (ar.skipReason == EntryAmountSkipReason.noRate
                ? 'No hourly rate on workspace'
                : '')
          : ar.formulaLine,
      child: Text(
        ar.displayAmount,
        style: t.textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
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
