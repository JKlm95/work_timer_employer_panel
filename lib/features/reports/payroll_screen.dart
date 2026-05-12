import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/employee_name_utils.dart';
import '../../core/utils/report_period.dart';
import '../../models/employer_group.dart';
import '../../models/tracked_employee.dart';
import '../../models/work_entry.dart';
import '../../services/export_service.dart';
import '../../services/firestore_service.dart';
import '../../services/report_calculation_service.dart';

class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key, required this.firestore});

  final FirestoreService firestore;

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  final _calc = ReportCalculationService();
  final _export = ExportService();

  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  String? _groupId;
  String? _trackedId;
  String _currency = 'all';
  bool _billableOnly = false;

  List<DateTime> _monthChoices() {
    final now = DateTime.now();
    final list = <DateTime>[];
    var d = DateTime(now.year, now.month);
    for (var i = 0; i < 24; i++) {
      list.add(DateTime(d.year, d.month));
      d = DateTime(d.year, d.month - 1);
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final employerUid = FirebaseAuth.instance.currentUser?.uid;
    if (employerUid == null) return const SizedBox.shrink();

    return StreamBuilder<List<TrackedEmployee>>(
      stream: widget.firestore.trackedEmployeesStream(employerUid),
      builder: (context, trackedSnap) {
        return StreamBuilder<List<EmployerGroup>>(
          stream: widget.firestore.groupsStream(employerUid),
          builder: (context, groupsSnap) {
            final trackedAll = trackedSnap.data ?? [];
            final groups = groupsSnap.data ?? [];

            var tracked = trackedAll;
            if (_groupId != null && _groupId!.isNotEmpty) {
              tracked = tracked.where((t) => t.groupIds.contains(_groupId)).toList();
            }
            if (_trackedId != null && _trackedId!.isNotEmpty) {
              tracked = tracked.where((t) => t.id == _trackedId).toList();
            }

            final period = monthContaining(_month);

            return Padding(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Monthly work report',
                              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Export CSV (PDF — TODO)',
                            onPressed: tracked.isEmpty
                                ? null
                                : () async {
                                    final bundle = await _buildLines(tracked, period);
                                    final fname = 'payroll-${DateFormat('yyyy-MM').format(_month)}.csv';
                                    _export.downloadPayrollCsv(filename: fname, lines: bundle.lines);
                                  },
                            icon: const Icon(Icons.download_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Based on tracked hours and workspace rates — not a legal payroll.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          DropdownButton<DateTime>(
                            value: DateTime(_month.year, _month.month),
                            items: [
                              for (final m in _monthChoices())
                                DropdownMenuItem<DateTime>(
                                  value: DateTime(m.year, m.month),
                                  child: Text(DateFormat.yMMMM().format(m)),
                                ),
                            ],
                            onChanged: (v) => setState(() {
                              if (v != null) _month = v;
                            }),
                          ),
                          DropdownButton<String?>(
                            value: _groupId,
                            hint: const Text('All groups'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('All groups')),
                              for (final g in groups)
                                DropdownMenuItem(value: g.id, child: Text(g.name)),
                            ],
                            onChanged: (v) => setState(() => _groupId = v),
                          ),
                          DropdownButton<String?>(
                            value: _trackedId,
                            hint: const Text('All employees'),
                            items: [
                              const DropdownMenuItem<String?>(value: null, child: Text('All employees')),
                              for (final t in trackedAll)
                                DropdownMenuItem(value: t.id, child: Text(employeeFullName(t))),
                            ],
                            onChanged: (v) => setState(() => _trackedId = v),
                          ),
                          DropdownButton<String>(
                            value: _currency,
                            items: const [
                              DropdownMenuItem(value: 'all', child: Text('All currencies')),
                              DropdownMenuItem(value: 'PLN', child: Text('PLN')),
                              DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                              DropdownMenuItem(value: 'USD', child: Text('USD')),
                              DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                            ],
                            onChanged: (v) => setState(() => _currency = v ?? 'all'),
                          ),
                          FilterChip(
                            label: const Text('Billable only'),
                            selected: _billableOnly,
                            onSelected: (v) => setState(() => _billableOnly = v),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Expanded(
                        child: trackedSnap.connectionState == ConnectionState.waiting && trackedAll.isEmpty
                            ? const Center(child: CircularProgressIndicator())
                            : tracked.isEmpty
                            ? Card(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'No payroll data for selected period.',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 16),
                                        OutlinedButton.icon(
                                          onPressed: () => context.go('/employees'),
                                          icon: const Icon(Icons.people_outline),
                                          label: const Text('Go to Employees'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : FutureBuilder<_PayrollBundle>(
                                future: _buildLines(tracked, period),
                                builder: (context, fut) {
                                  if (!fut.hasData) {
                                    return const Center(child: CircularProgressIndicator());
                                  }
                                  var lines = fut.data!.lines;
                                  if (_currency != 'all') {
                                    lines = lines
                                        .map((line) {
                                          final m = Map<String, double>.from(line.amountByCurrency);
                                          for (final k in m.keys.toList()) {
                                            if (k != _currency) m.remove(k);
                                          }
                                          return PayrollLine(
                                            trackedId: line.trackedId,
                                            employeeLabel: line.employeeLabel,
                                            companyName: line.companyName,
                                            groupLabels: line.groupLabels,
                                            totalHours: line.totalHours,
                                            billableHours: line.billableHours,
                                            nonBillableHours: line.nonBillableHours,
                                            vacationCount: line.vacationCount,
                                            sickCount: line.sickCount,
                                            amountByCurrency: m,
                                            amountDisplay: _payrollAmountDisplay(m, _currency),
                                            currencyDisplay: _payrollCurrencyDisplay(m, _currency),
                                          );
                                        })
                                        .toList();
                                  }

                                  final bundle = fut.data!;
                                  return Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      LayoutBuilder(
                                        builder: (context, c) {
                                          final w = c.maxWidth;
                                          final cardW = w > 900 ? (w - 48) / 4 : (w > 500 ? (w - 16) / 2 : w);
                                          Widget card(String title, String value) {
                                            return SizedBox(
                                              width: cardW,
                                              child: Card(
                                                child: Padding(
                                                  padding: const EdgeInsets.all(14),
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    children: [
                                                      Text(
                                                        title,
                                                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 6),
                                                      Text(
                                                        value,
                                                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                          fontWeight: FontWeight.w700,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          }

                                          return Wrap(
                                            spacing: 12,
                                            runSpacing: 12,
                                            children: [
                                              card('Tracked employees', '${lines.length}'),
                                              card('Total hours', bundle.totalHours.toStringAsFixed(2)),
                                              card('Billable hours', bundle.totalBillableHours.toStringAsFixed(2)),
                                              card('Estimated (billable)', _money(bundle.grandTotals)),
                                            ],
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      Card(
                                        child: SingleChildScrollView(
                                          scrollDirection: Axis.horizontal,
                                          child: DataTable(
                                            headingRowHeight: 48,
                                            dataRowMinHeight: 48,
                                            dataRowMaxHeight: 72,
                                            columns: const [
                                              DataColumn(label: Text('Employee')),
                                              DataColumn(label: Text('Company')),
                                              DataColumn(label: Text('Total h')),
                                              DataColumn(label: Text('Billable h')),
                                              DataColumn(label: Text('Non-bill. h')),
                                              DataColumn(label: Text('Estimated')),
                                              DataColumn(label: Text('Currency')),
                                            ],
                                            rows: [
                                              for (final line in lines)
                                                DataRow(
                                                  cells: [
                                                    DataCell(Text(line.employeeLabel)),
                                                    DataCell(Text(line.companyName)),
                                                    DataCell(Text(line.totalHours.toStringAsFixed(2))),
                                                    DataCell(Text(line.billableHours.toStringAsFixed(2))),
                                                    DataCell(Text(line.nonBillableHours.toStringAsFixed(2))),
                                                    DataCell(Text(line.amountDisplay)),
                                                    DataCell(Text(line.currencyDisplay)),
                                                  ],
                                                ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Card(
                                        child: Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                'Summary',
                                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text('Totals by currency: ${_money(bundle.grandTotals)}'),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<_PayrollBundle> _buildLines(List<TrackedEmployee> tracked, ReportPeriod period) async {
    final lines = <PayrollLine>[];
    var grandTotals = <String, double>{};
    var totalHoursAll = 0.0;
    var totalBillableAll = 0.0;

    final groupsSnap = await widget.firestore.groupsStream(FirebaseAuth.instance.currentUser!.uid).first;
    final groupName = {for (final g in groupsSnap) g.id: g.name};

    for (final t in tracked) {
      final entries = await widget.firestore.fetchEntriesInRange(t.employeeUid, period);
      final workspaces = await widget.firestore.fetchEmployeeWorkspaces(t.employeeUid);
      final wsMap = {for (final w in workspaces) w.id: w};

      final scoped = entries.where((e) {
        if (e.isDeleted || e.end == null) return false;
        final ws = wsMap[e.workspaceId];
        return ws?.companySlug?.toLowerCase() == t.companySlug.toLowerCase();
      }).toList();

      final active = _billableOnly
          ? scoped.where((e) => e.isWorkEntry && e.effectiveBillable).toList()
          : scoped;

      final split = _calc.splitHours(active);

      final totalRowHours = _sumHours(active);
      totalHoursAll += totalRowHours;
      totalBillableAll += split.billableWorkHours;

      final money = _calc.estimatedAmountByCurrency(
        entries: active.where((e) => e.isWorkEntry).toList(),
        workspaceById: wsMap,
      );
      money.forEach((k, v) => grandTotals[k] = (grandTotals[k] ?? 0) + v);

      final groupLabels = t.groupIds.map((id) => groupName[id] ?? id).join(', ');

      lines.add(
        PayrollLine(
          trackedId: t.id,
          employeeLabel: employeeFullName(t),
          companyName: t.companyName,
          groupLabels: groupLabels.isEmpty ? '—' : groupLabels,
          totalHours: totalRowHours,
          billableHours: split.billableWorkHours,
          nonBillableHours: split.nonBillableWorkHours,
          vacationCount: split.vacationEntries,
          sickCount: split.sickEntries,
          amountByCurrency: money,
          amountDisplay: _payrollAmountDisplay(money, _currency),
          currencyDisplay: _payrollCurrencyDisplay(money, _currency),
        ),
      );
    }

    return _PayrollBundle(
      lines: lines,
      grandTotals: grandTotals,
      totalHours: totalHoursAll,
      totalBillableHours: totalBillableAll,
    );
  }

  String _payrollAmountDisplay(Map<String, double> m, String filter) {
    if (m.isEmpty) return '—';
    if (filter == 'all') return _money(m);
    final v = m[filter];
    return v != null && v > 0 ? v.toStringAsFixed(2) : '—';
  }

  String _payrollCurrencyDisplay(Map<String, double> m, String filter) {
    if (m.isEmpty) return '—';
    if (filter != 'all') return filter;
    if (m.length == 1) return m.keys.first;
    return 'Various';
  }

  static String _money(Map<String, double> m) {
    if (m.isEmpty) return '—';
    return m.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · ');
  }

  double _sumHours(List<WorkEntry> entries) {
    var s = 0.0;
    for (final e in entries) {
      if (e.end == null) continue;
      s += e.duration!.inMinutes / 60.0;
    }
    return s;
  }
}

class _PayrollBundle {
  _PayrollBundle({
    required this.lines,
    required this.grandTotals,
    required this.totalHours,
    required this.totalBillableHours,
  });

  final List<PayrollLine> lines;
  final Map<String, double> grandTotals;
  final double totalHours;
  final double totalBillableHours;
}
