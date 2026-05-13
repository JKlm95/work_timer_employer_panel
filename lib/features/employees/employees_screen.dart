import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_layout.dart';
import '../../core/utils/employee_name_utils.dart';
import '../../core/utils/report_period.dart';
import '../../core/widgets/app_empty_state.dart';
import '../../core/widgets/app_pulse_loading.dart';
import '../../core/widgets/app_pinned_toolbar.dart';
import '../../core/widgets/employee_avatar.dart';
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
  final _searchCtrl = TextEditingController();

  List<TrackedEmployee> _filtered(List<TrackedEmployee> tracked) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return tracked;
    return tracked.where((t) {
      return employeeFullName(t).toLowerCase().contains(q) ||
          t.employeeEmail.toLowerCase().contains(q) ||
          t.companyName.toLowerCase().contains(q);
    }).toList();
  }

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
    _searchCtrl.dispose();
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
            if (trackedSnap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: _EmployeesLoadError(
                  title: 'Could not load employees',
                  detail: '${trackedSnap.error}',
                ),
              );
            }
            if (groupsSnap.hasError) {
              return Padding(
                padding: const EdgeInsets.all(24),
                child: _EmployeesLoadError(
                  title: 'Could not load groups',
                  detail: '${groupsSnap.error}',
                ),
              );
            }

            final tracked = trackedSnap.data ?? [];
            final groups = groupsSnap.data ?? [];
            if (trackedSnap.connectionState == ConnectionState.waiting &&
                !trackedSnap.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppLayout.pagePadding),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppPulseLoading(rows: 5),
                        const SizedBox(height: 18),
                        Text(
                          'Loading employees…',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            final visible = _filtered(tracked);

            return Padding(
              padding: const EdgeInsets.all(AppLayout.pagePadding),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1400),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppToolbarSurface(
                        child: LayoutBuilder(
                          builder: (context, c) {
                            final narrow = c.maxWidth < 720;
                            final search = SizedBox(
                              width: narrow ? double.infinity : 260,
                              child: TextField(
                                controller: _searchCtrl,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  hintText: 'Search name, email, company…',
                                  isDense: true,
                                  prefixIcon: Icon(Icons.search, size: 22),
                                ),
                              ),
                            );
                            final actions = Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.end,
                              children: [
                                if (_lastMonthRefresh != null)
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 8,
                                    ),
                                    child: Text(
                                      'Updated ${DateFormat.Hms().format(_lastMonthRefresh!)}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ),
                                IconButton.filledTonal(
                                  tooltip: 'Refresh data',
                                  onPressed: tracked.isEmpty || _monthRefreshing
                                      ? null
                                      : () => _manualMonthRefresh(uid),
                                  icon: _monthRefreshing
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.refresh_rounded),
                                ),
                                OutlinedButton.icon(
                                  onPressed: () async {
                                    final messenger = ScaffoldMessenger.of(
                                      context,
                                    );
                                    messenger.showSnackBar(
                                      const SnackBar(
                                        content: Text(
                                          'Syncing names from directory…',
                                        ),
                                      ),
                                    );
                                    final n = await widget.firestore
                                        .syncTrackedEmployeeProfilesFromIndex(
                                          uid,
                                        );
                                    if (!context.mounted) return;
                                    messenger.hideCurrentSnackBar();
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          n == 0
                                              ? 'No name updates (index empty or already up to date).'
                                              : 'Updated $n employee(s).',
                                        ),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.sync_outlined),
                                  label: const Text('Sync names'),
                                ),
                                FilledButton.icon(
                                  onPressed: () => showAddEmployeeDialog(
                                    context,
                                    widget.firestore,
                                  ),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: const Text('Add employee'),
                                ),
                              ],
                            );
                            if (narrow) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'Employees',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 10),
                                  search,
                                  const SizedBox(height: 10),
                                  actions,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Employees',
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      Text(
                                        'Search, refresh, or add people you track.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                search,
                                const SizedBox(width: 12),
                                Flexible(child: actions),
                              ],
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: AppLayout.blockGap),
                      Expanded(
                        child: tracked.isEmpty
                            ? Card(
                                child: AppEmptyState(
                                  icon: Icons.group_add_outlined,
                                  title: 'No employees tracked yet',
                                  subtitle:
                                      'Add an employee by work email and company name.',
                                  action: FilledButton.icon(
                                    onPressed: () => showAddEmployeeDialog(
                                      context,
                                      widget.firestore,
                                    ),
                                    icon: const Icon(
                                      Icons.person_add_alt_1_outlined,
                                    ),
                                    label: const Text('Add employee'),
                                  ),
                                ),
                              )
                            : visible.isEmpty
                            ? Card(
                                child: AppEmptyState(
                                  icon: Icons.search_off_rounded,
                                  title: 'No employees match your search',
                                  subtitle:
                                      'Try a different keyword or clear the search field.',
                                  action: OutlinedButton.icon(
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() {});
                                    },
                                    icon: const Icon(Icons.clear),
                                    label: const Text('Clear search'),
                                  ),
                                ),
                              )
                            : Card(
                                clipBehavior: Clip.antiAlias,
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth:
                                          MediaQuery.sizeOf(context).width - 48,
                                    ),
                                    child: _EmployeesTable(
                                      key: ValueKey(
                                        '${visible.map((e) => e.id).join(',')}_$_monthRefreshNonce',
                                      ),
                                      tracked: visible,
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
      future: _loadMonth(widget.tracked, widget.firestore, widget.employerUid),
      builder: (context, snap) {
        if (snap.hasError) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Material(
                color: Theme.of(
                  context,
                ).colorScheme.errorContainer.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Could not load monthly totals for the table. Hours and amounts may show as 0.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onErrorContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _buildTable(
                context,
                snap.data ?? const {},
                snap.connectionState == ConnectionState.waiting,
              ),
            ],
          );
        }
        final month = snap.data ?? {};
        final loading = snap.connectionState == ConnectionState.waiting;
        return _buildTable(context, month, loading);
      },
    );
  }

  Widget _buildTable(
    BuildContext context,
    Map<String, _EmpMonth> month,
    bool loading,
  ) {
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
                    EmployeeAvatar(
                      seed: t.employeeUid,
                      initials: employeeInitials(t),
                      radius: 20,
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
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
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
              DataCell(
                Tooltip(
                  message: t.companyName,
                  child: Text(
                    t.companyName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              DataCell(Text(_groupLabels(t, widget.groups))),
              DataCell(
                Text(
                  loading
                      ? '…'
                      : (month[t.id]?.hours.toStringAsFixed(1) ?? '0'),
                ),
              ),
              DataCell(
                Text(
                  loading
                      ? '…'
                      : _money(month[t.id]?.amountByCurrency ?? const {}),
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
                        if (ok == true && context.mounted) {
                          await widget.firestore.removeTrackedEmployee(
                            widget.employerUid,
                            t.id,
                            employerEmail:
                                FirebaseAuth.instance.currentUser?.email ?? '',
                          );
                        }
                      },
                      child: Text(
                        'Remove',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
      ],
    );
  }

  Future<Map<String, _EmpMonth>> _loadMonth(
    List<TrackedEmployee> tracked,
    FirestoreService fs,
    String employerUid,
  ) async {
    final period = monthContaining(DateTime.now());
    final out = <String, _EmpMonth>{};
    for (final t in tracked) {
      final entries = await fs.fetchEntriesInRangeForEmployer(
        employerUid,
        t.employeeUid,
        period,
      );
      final workspaces = await fs.fetchEmployeeWorkspacesForEmployer(
        employerUid,
        t.employeeUid,
      );
      final wsMap = {for (final w in workspaces) w.id: w};
      final filtered = entries.where((e) {
        if (e.isDeleted || e.end == null) return false;
        if (wsMap[e.workspaceId] == null) return false;
        return wsMap[e.workspaceId]?.companySlug?.toLowerCase() ==
            t.companySlug.toLowerCase();
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
    return m.entries
        .map((e) => '${e.key} ${e.value.toStringAsFixed(2)}')
        .join(' · ');
  }
}

class _EmpMonth {
  _EmpMonth({required this.hours, required this.amountByCurrency});

  final double hours;
  final Map<String, double> amountByCurrency;
}

class _EmployeesLoadError extends StatelessWidget {
  const _EmployeesLoadError({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppLayout.pagePadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: AppEmptyState(
              icon: Icons.cloud_off_outlined,
              iconColor: scheme.error,
              title: title,
              subtitle: detail,
              detailSelectable: true,
            ),
          ),
        ),
      ),
    );
  }
}
