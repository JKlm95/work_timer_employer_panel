import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/employee_name_utils.dart';
import '../../core/utils/report_period.dart';
import '../../core/widgets/employee_presence_badge.dart';
import '../../models/employer_group.dart';
import '../../models/tracked_employee.dart';
import '../../services/firestore_service.dart';
import '../../services/report_calculation_service.dart';
import 'widgets/add_employee_dialog.dart';
import 'widgets/assign_groups_sheet.dart';

class EmployeesScreen extends StatefulWidget {
  const EmployeesScreen({super.key, required this.firestore});

  final FirestoreService firestore;

  @override
  State<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends State<EmployeesScreen> {
  int _monthRefreshNonce = 0;
  bool _monthRefreshing = false;
  DateTime? _lastMonthRefresh;
  Timer? _autoMonthTimer;

  @override
  void initState() {
    super.initState();
    _autoMonthTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      setState(() => _monthRefreshNonce++);
    });
  }

  @override
  void dispose() {
    _autoMonthTimer?.cancel();
    super.dispose();
  }

  Future<void> _manualMonthRefresh(String employerUid) async {
    setState(() => _monthRefreshing = true);
    try {
      await widget.firestore.ensureTrackedEmployeeUidAccessDocs(employerUid);
      if (mounted) {
        setState(() {
          _monthRefreshNonce++;
          _lastMonthRefresh = DateTime.now();
        });
      }
    } finally {
      if (mounted) setState(() => _monthRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<TrackedEmployee>>(
      stream: widget.firestore.trackedEmployeesStream(uid),
      builder: (context, trackedSnap) {
        return StreamBuilder<List<EmployerGroup>>(
          stream: widget.firestore.groupsStream(uid),
          builder: (context, groupsSnap) {
            final tracked = trackedSnap.data ?? [];
            final groups = groupsSnap.data ?? [];
            if (trackedSnap.connectionState == ConnectionState.waiting && !trackedSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

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
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            'Employees',
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          if (_lastMonthRefresh != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Text(
                                'Last updated: ${DateFormat.Hms().format(_lastMonthRefresh!)}',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          IconButton(
                            tooltip: 'Refresh data',
                            onPressed: tracked.isEmpty || _monthRefreshing ? null : () => _manualMonthRefresh(uid),
                            icon: _monthRefreshing
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.refresh),
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              messenger.showSnackBar(
                                const SnackBar(content: Text('Syncing names from directory…')),
                              );
                              final n = await widget.firestore.syncTrackedEmployeeProfilesFromIndex(uid);
                              if (!context.mounted) return;
                              messenger.hideCurrentSnackBar();
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    n == 0 ? 'No name updates (index empty or already up to date).' : 'Updated $n employee(s).',
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.sync_outlined),
                            label: const Text('Sync names'),
                          ),
                          const SizedBox(width: 12),
                          FilledButton.icon(
                            onPressed: () => showAddEmployeeDialog(context, widget.firestore),
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Add employee'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      Expanded(
                        child: tracked.isEmpty
                            ? Card(
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          'No employees tracked yet.',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Add an employee by work email and company name.',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        FilledButton.icon(
                                          onPressed: () => showAddEmployeeDialog(context, widget.firestore),
                                          icon: const Icon(Icons.person_add_alt_1_outlined),
                                          label: const Text('Add employee'),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            : Card(
                                clipBehavior: Clip.antiAlias,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 48),
                                    child: _EmployeesTable(
                                      key: ValueKey(
                                        '${tracked.map((e) => e.id).join(',')}_$_monthRefreshNonce',
                                      ),
                                      tracked: tracked,
                                      groups: groups,
                                      firestore: widget.firestore,
                                      employerUid: uid,
                                    ),
                                  ),
                                ),
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
}

class _EmployeesTable extends StatefulWidget {
  const _EmployeesTable({
    super.key,
    required this.tracked,
    required this.groups,
    required this.firestore,
    required this.employerUid,
  });

  final List<TrackedEmployee> tracked;
  final List<EmployerGroup> groups;
  final FirestoreService firestore;
  final String employerUid;

  @override
  State<_EmployeesTable> createState() => _EmployeesTableState();
}

class _EmployeesTableState extends State<_EmployeesTable> {
  final _calc = ReportCalculationService();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, _EmpMonth>>(
      future: _loadMonth(widget.tracked, widget.firestore),
      builder: (context, snap) {
        final month = snap.data ?? {};
        final loading = snap.connectionState == ConnectionState.waiting;
        return DataTable(
          headingRowHeight: 48,
          dataRowMinHeight: 52,
          dataRowMaxHeight: 88,
          columns: const [
            DataColumn(label: Text('Employee')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('Company')),
            DataColumn(label: Text('Groups')),
            DataColumn(label: Text('Hours (month)')),
            DataColumn(label: Text('Est. amount')),
            DataColumn(label: Text('Actions')),
          ],
          rows: [
            for (final t in widget.tracked)
              DataRow(
                cells: [
                  DataCell(
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        CircleAvatar(
                          radius: 20,
                          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                          child: Text(
                            employeeInitials(t),
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                employeeFullName(t),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              if (employeeShowEmailAsSubtitle(t))
                                Text(
                                  t.employeeEmail,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  DataCell(
                    EmployeePresenceBadge(
                      firestore: widget.firestore,
                      tracked: t,
                      compact: true,
                    ),
                  ),
                  DataCell(Text(t.companyName)),
                  DataCell(Text(_groupLabels(t, widget.groups))),
                  DataCell(Text(loading ? '…' : (month[t.id]?.hours.toStringAsFixed(1) ?? '0'))),
                  DataCell(
                    Text(
                      loading ? '…' : _money(month[t.id]?.amountByCurrency ?? const {}),
                    ),
                  ),
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => context.go('/employees/detail/${t.id}'),
                          child: const Text('View'),
                        ),
                        TextButton(
                          onPressed: () => showAssignGroupsSheet(
                            context,
                            firestore: widget.firestore,
                            employerUid: widget.employerUid,
                            tracked: t,
                            allGroups: widget.groups,
                          ),
                          child: const Text('Groups'),
                        ),
                        TextButton(
                          onPressed: () async {
                            final ok = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text('Remove employee'),
                                content: const Text(
                                  'Remove employee from employer panel? '
                                  'This only removes them from your list — their account, projects and time entries are not deleted.',
                                ),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
                                  FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Remove')),
                                ],
                              ),
                            );
                            if (ok == true && context.mounted) {
                              await widget.firestore.removeTrackedEmployee(widget.employerUid, t.id);
                            }
                          },
                          child: Text('Remove', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        );
      },
    );
  }

  Future<Map<String, _EmpMonth>> _loadMonth(List<TrackedEmployee> tracked, FirestoreService fs) async {
    final period = monthContaining(DateTime.now());
    final out = <String, _EmpMonth>{};
    for (final t in tracked) {
      final entries = await fs.fetchEntriesInRange(t.employeeUid, period);
      final workspaces = await fs.fetchEmployeeWorkspaces(t.employeeUid);
      final wsMap = {for (final w in workspaces) w.id: w};
      final filtered = entries.where((e) {
        if (e.isDeleted || e.end == null) return false;
        return wsMap[e.workspaceId]?.companySlug?.toLowerCase() == t.companySlug.toLowerCase();
      }).toList();
      final hours = _calc.hoursForEntries(filtered);
      final money = _calc.estimatedAmountByCurrency(
        entries: filtered.where((e) => e.isWorkEntry).toList(),
        workspaceById: wsMap,
      );
      out[t.id] = _EmpMonth(hours: hours, amountByCurrency: money);
    }
    return out;
  }

  static String _groupLabels(TrackedEmployee t, List<EmployerGroup> groups) {
    if (t.groupIds.isEmpty) return '—';
    final map = {for (final g in groups) g.id: g.name};
    return t.groupIds.map((id) => map[id] ?? id).join(', ');
  }

  static String _money(Map<String, double> m) {
    if (m.isEmpty) return '—';
    return m.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · ');
  }
}

class _EmpMonth {
  _EmpMonth({required this.hours, required this.amountByCurrency});

  final double hours;
  final Map<String, double> amountByCurrency;
}
