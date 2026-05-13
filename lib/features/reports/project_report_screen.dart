import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/utils/report_period.dart';
import '../../models/tracked_employee.dart';
import '../../models/work_entry.dart';
import '../../models/workspace.dart' as ws;
import '../employees/widgets/edit_workspace_billing_dialog.dart';
import '../../services/export_service.dart';
import '../../services/firestore_service.dart';
import '../../services/report_calculation_service.dart';

class ProjectReportScreen extends StatefulWidget {
  const ProjectReportScreen({
    super.key,
    required this.firestore,
    required this.trackedId,
    required this.workspaceId,
  });

  final FirestoreService firestore;
  final String trackedId;
  final String workspaceId;

  @override
  State<ProjectReportScreen> createState() => _ProjectReportScreenState();
}

class _ProjectReportScreenState extends State<ProjectReportScreen> {
  final _calc = ReportCalculationService();
  final _export = ExportService();

  /// Bumps after editing workspace billing so rates reload from Firestore.
  int _workspaceReloadKey = 0;

  DateRangePreset _preset = DateRangePreset.thisMonth;
  DateTimeRange? _custom;
  bool _billableOnly = false;
  String _entryType = 'all';

  ReportPeriod _period() {
    final now = DateTime.now();
    switch (_preset) {
      case DateRangePreset.thisMonth:
        return monthContaining(now);
      case DateRangePreset.previousMonth:
        return previousMonthFrom(now);
      case DateRangePreset.custom:
        final r = _custom;
        if (r == null) return monthContaining(now);
        final end = DateTime(
          r.end.year,
          r.end.month,
          r.end.day,
          23,
          59,
          59,
          999,
        );
        return ReportPeriod(
          start: DateTime(r.start.year, r.start.month, r.start.day),
          endInclusive: end,
        );
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial =
        _custom ??
        DateTimeRange(start: DateTime(now.year, now.month), end: now);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );
    if (picked != null) {
      setState(() {
        _custom = picked;
        _preset = DateRangePreset.custom;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final employerUid = FirebaseAuth.instance.currentUser?.uid;
    if (employerUid == null) return const SizedBox.shrink();

    return StreamBuilder<List<TrackedEmployee>>(
      stream: widget.firestore.trackedEmployeesStream(employerUid),
      builder: (context, snap) {
        final list = snap.data ?? [];
        TrackedEmployee? tracked;
        for (final t in list) {
          if (t.id == widget.trackedId) tracked = t;
        }
        if (tracked == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Report')),
            body: const Center(child: Text('Employee not found.')),
          );
        }

        final TrackedEmployee te = tracked;

        return FutureBuilder<List<ws.Workspace>>(
          key: ValueKey(
            '${te.employeeUid}_${widget.workspaceId}_$_workspaceReloadKey',
          ),
          future: widget.firestore.fetchEmployeeWorkspaces(te.employeeUid),
          builder: (context, wsSnap) {
            if (!wsSnap.hasData) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            ws.Workspace? selectedWs;
            for (final w in wsSnap.data!) {
              if (w.id == widget.workspaceId) selectedWs = w;
            }
            if (selectedWs == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Report')),
                body: const Center(child: Text('Project not found.')),
              );
            }

            final workspace = selectedWs;
            final period = _period();

            return FutureBuilder<List<WorkEntry>>(
              future: widget.firestore.fetchEntriesInRange(
                te.employeeUid,
                period,
              ),
              builder: (context, entSnap) {
                if (!entSnap.hasData) {
                  return Scaffold(
                    appBar: AppBar(title: Text(workspace.name)),
                    body: const Center(child: CircularProgressIndicator()),
                  );
                }

                final raw = entSnap.data!
                    .where((e) => e.workspaceId == widget.workspaceId)
                    .toList();
                final visible = _calc.visibleEntries(
                  raw,
                  period: period,
                  billableOnly: _billableOnly,
                  entryTypeFilter: _entryType,
                );
                final split = _calc.splitHours(
                  raw
                      .where((e) => e.workspaceId == widget.workspaceId)
                      .toList(),
                );
                final money = _calc.estimatedAmountByCurrency(
                  entries: visible.where((e) => e.isWorkEntry).toList(),
                  workspaceById: {workspace.id: workspace},
                );

                final totalHours = _calc.hoursForEntries(visible);

                return Scaffold(
                  appBar: AppBar(
                    title: Text(workspace.name),
                    actions: [
                      IconButton(
                        tooltip: 'Edit hourly rate / currency',
                        onPressed: () async {
                          await showEditWorkspaceBillingDialog(
                            context,
                            firestore: widget.firestore,
                            employeeUid: te.employeeUid,
                            workspace: workspace,
                          );
                          if (mounted) setState(() => _workspaceReloadKey++);
                        },
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Export CSV (PDF export — TODO)',
                        onPressed: () {
                          final fname =
                              'project-report-${DateFormat('yyyyMMdd').format(DateTime.now())}.csv';
                          _export.downloadProjectReportCsv(
                            filename: fname,
                            entries: visible,
                            workspaceById: {workspace.id: workspace},
                            billableOnly: _billableOnly,
                          );
                        },
                        icon: const Icon(Icons.download_outlined),
                      ),
                    ],
                  ),
                  body: SingleChildScrollView(
                    padding: const EdgeInsets.all(24),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Estimates use tracked hours and workspace hourly rates — not legal invoicing.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 12,
                              runSpacing: 12,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SegmentedButton<DateRangePreset>(
                                  segments: const [
                                    ButtonSegment(
                                      value: DateRangePreset.thisMonth,
                                      label: Text('This month'),
                                    ),
                                    ButtonSegment(
                                      value: DateRangePreset.previousMonth,
                                      label: Text('Previous'),
                                    ),
                                    ButtonSegment(
                                      value: DateRangePreset.custom,
                                      label: Text('Custom'),
                                    ),
                                  ],
                                  selected: {_preset},
                                  onSelectionChanged: (s) {
                                    setState(() => _preset = s.first);
                                  },
                                ),
                                if (_preset == DateRangePreset.custom)
                                  OutlinedButton.icon(
                                    onPressed: _pickCustomRange,
                                    icon: const Icon(Icons.date_range),
                                    label: Text(
                                      _custom == null
                                          ? 'Pick dates'
                                          : '${DateFormat.yMMMd().format(_custom!.start)} — ${DateFormat.yMMMd().format(_custom!.end)}',
                                    ),
                                  ),
                                FilterChip(
                                  label: const Text('Billable only'),
                                  selected: _billableOnly,
                                  onSelected: (v) =>
                                      setState(() => _billableOnly = v),
                                ),
                                DropdownButton<String>(
                                  value: _entryType,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('All types'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'work',
                                      child: Text('Work'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'vacation',
                                      child: Text('Vacation'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'sickLeave',
                                      child: Text('Sick leave'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'businessTrip',
                                      child: Text('Business trip'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'other',
                                      child: Text('Other'),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => _entryType = v ?? 'all'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            LayoutBuilder(
                              builder: (context, c) {
                                final w = c.maxWidth;
                                final cols = w > 900 ? 3 : 1;
                                final cards = [
                                  _SummaryTile(
                                    title: 'Total hours',
                                    value: totalHours.toStringAsFixed(2),
                                  ),
                                  _SummaryTile(
                                    title: 'Billable / non-billable (work)',
                                    value:
                                        '${split.billableWorkHours.toStringAsFixed(2)} / ${split.nonBillableWorkHours.toStringAsFixed(2)}',
                                  ),
                                  _SummaryTile(
                                    title: 'Vacation / sick / trip entries',
                                    value:
                                        '${split.vacationEntries} / ${split.sickEntries} / ${split.businessTripEntries}',
                                  ),
                                  _SummaryTile(
                                    title: 'Estimated amount',
                                    value: money.isEmpty
                                        ? '—'
                                        : money.entries
                                              .map(
                                                (e) =>
                                                    '${e.key} ${e.value.toStringAsFixed(2)}',
                                              )
                                              .join(' · '),
                                  ),
                                ];
                                return Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: [
                                    for (var i = 0; i < cards.length; i++)
                                      SizedBox(
                                        width: cols == 1 ? w : (w - 24) / 2,
                                        child: cards[i],
                                      ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            Card(
                              clipBehavior: Clip.antiAlias,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: DataTable(
                                  columns: const [
                                    DataColumn(label: Text('Date')),
                                    DataColumn(label: Text('Start')),
                                    DataColumn(label: Text('End')),
                                    DataColumn(label: Text('Duration')),
                                    DataColumn(label: Text('Type')),
                                    DataColumn(label: Text('Billable')),
                                    DataColumn(label: Text('Task')),
                                    DataColumn(label: Text('Note')),
                                    DataColumn(label: Text('Amount')),
                                  ],
                                  rows: [
                                    for (final e in visible)
                                      DataRow(
                                        cells: [
                                          DataCell(
                                            Text(
                                              DateFormat.yMMMd().format(
                                                e.start,
                                              ),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              DateFormat.Hm().format(e.start),
                                            ),
                                          ),
                                          DataCell(
                                            Text(
                                              e.end != null
                                                  ? DateFormat.Hm().format(
                                                      e.end!,
                                                    )
                                                  : '—',
                                            ),
                                          ),
                                          DataCell(Text(_dur(e))),
                                          DataCell(Text(e.entryType ?? 'work')),
                                          DataCell(
                                            Text(
                                              e.effectiveBillable
                                                  ? 'yes'
                                                  : 'no',
                                            ),
                                          ),
                                          DataCell(Text(e.taskTitle ?? '')),
                                          DataCell(Text(e.note ?? '')),
                                          DataCell(
                                            Text(_amountCell(e, workspace)),
                                          ),
                                        ],
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  String _dur(WorkEntry e) {
    final d = e.duration;
    if (d == null) return '—';
    final h = d.inMinutes / 60.0;
    return '${h.toStringAsFixed(2)} h';
  }

  String _amountCell(WorkEntry e, ws.Workspace ws) {
    if (!e.isWorkEntry) return '—';
    if (_billableOnly && !e.effectiveBillable) return '—';
    final rate = ws.hourlyRate;
    if (rate == null || rate <= 0) return '—';
    final d = e.duration;
    if (d == null) return '—';
    final amount = d.inMinutes / 60.0 * rate;
    return '${ws.currency ?? ''} ${amount.toStringAsFixed(2)}'.trim();
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}
