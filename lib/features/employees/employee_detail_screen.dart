import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/employee_name_utils.dart';
import '../../core/utils/email_domain_utils.dart';
import '../../core/utils/report_period.dart';
import '../../core/widgets/employee_presence_badge.dart';
import '../../models/employer_group.dart';
import '../../models/tracked_employee.dart';
import '../../models/work_entry.dart';
import '../../models/workspace.dart' as ws;
import '../../services/firestore_service.dart';
import '../../services/report_calculation_service.dart';
import 'widgets/edit_workspace_billing_dialog.dart';

class EmployeeDetailScreen extends StatefulWidget {
  const EmployeeDetailScreen({super.key, required this.firestore, required this.trackedId});

  final FirestoreService firestore;
  final String trackedId;

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  int _workspaceEpoch = 0;

  void _reloadWorkspaces() => setState(() => _workspaceEpoch++);

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final employerDomain = emailDomain(FirebaseAuth.instance.currentUser?.email ?? '');
    if (uid == null || employerDomain == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return StreamBuilder<List<TrackedEmployee>>(
      stream: widget.firestore.trackedEmployeesStream(uid),
      builder: (context, trackedSnap) {
        return StreamBuilder<List<EmployerGroup>>(
          stream: widget.firestore.groupsStream(uid),
          builder: (context, groupsSnap) {
            final list = trackedSnap.data ?? [];
            TrackedEmployee? tracked;
            for (final t in list) {
              if (t.id == widget.trackedId) tracked = t;
            }
            if (trackedSnap.connectionState == ConnectionState.waiting && tracked == null) {
              return const Scaffold(body: Center(child: CircularProgressIndicator()));
            }
            if (tracked == null) {
              return Scaffold(
                appBar: AppBar(title: const Text('Employee')),
                body: const Center(child: Text('Employee not found on your list.')),
              );
            }

            final TrackedEmployee tr = tracked;
            final groups = groupsSnap.data ?? [];
            final groupName = {for (final g in groups) g.id: g.name};
            final groupLabels = tr.groupIds.map((id) => groupName[id] ?? id).join(', ');

            return Scaffold(
              appBar: AppBar(
                title: Text(employeeFullName(tr)),
                actions: [
                  IconButton(
                    tooltip: 'Refresh name from directory',
                    icon: const Icon(Icons.person_search_outlined),
                    onPressed: () async {
                      final ok = await widget.firestore.syncTrackedEmployeeProfileFromIndex(uid, tr.id);
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok ? 'Name fields updated from user email index.' : 'No changes, or index not available.',
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
              body: FutureBuilder<List<ws.Workspace>>(
                key: ValueKey('${tr.id}_$_workspaceEpoch'),
                future: widget.firestore.fetchEmployeeWorkspaces(tr.employeeUid),
                builder: (context, wsSnap) {
                  if (!wsSnap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final workspaces = wsSnap.data!
                      .where((w) {
                        final slugOk = (w.companySlug ?? '').toLowerCase() == tr.companySlug.toLowerCase();
                        final dom = w.employeeWorkEmailDomain?.toLowerCase();
                        final domOk = dom != null && dom == employerDomain;
                        return slugOk && domOk;
                      })
                      .toList();

                  final calc = ReportCalculationService();
                  final period = monthContaining(DateTime.now());

                  return FutureBuilder<_EmpHeaderStats>(
                    future: _loadHeaderStats(tr, period, calc),
                    builder: (context, hdr) {
                      final stats = hdr.data;
                      return SingleChildScrollView(
                        padding: const EdgeInsets.all(24),
                        child: Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 960),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            CircleAvatar(
                                              radius: 28,
                                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                              child: Text(
                                                employeeInitials(tr),
                                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    employeeFullName(tr),
                                                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                  if (employeeShowEmailAsSubtitle(tr)) ...[
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      tr.employeeEmail,
                                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                      ),
                                                    ),
                                                  ],
                                                  const SizedBox(height: 8),
                                                  Text('Company: ${tr.companyName}'),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    groupLabels.isEmpty ? 'Groups: —' : 'Groups: $groupLabels',
                                                    style: Theme.of(context).textTheme.bodyMedium,
                                                  ),
                                                  const SizedBox(height: 12),
                                                  Wrap(
                                                    spacing: 12,
                                                    runSpacing: 8,
                                                    crossAxisAlignment: WrapCrossAlignment.center,
                                                    children: [
                                                      EmployeePresenceBadge(
                                                        firestore: widget.firestore,
                                                        tracked: tr,
                                                      ),
                                                      FutureBuilder<DateTime?>(
                                                        future: widget.firestore.fetchLastActivityAt(tr.employeeUid),
                                                        builder: (context, la) {
                                                          final d = la.data;
                                                          final text = d == null
                                                              ? 'Last activity: —'
                                                              : 'Last activity: ${DateFormat.yMMMd().add_jm().format(d)}';
                                                          return Text(
                                                            text,
                                                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                            ),
                                                          );
                                                        },
                                                      ),
                                                    ],
                                                  ),
                                                  if (stats != null) ...[
                                                    const SizedBox(height: 16),
                                                    Wrap(
                                                      spacing: 12,
                                                      runSpacing: 8,
                                                      children: [
                                                        _infoChip(
                                                          context,
                                                          'Hours this month',
                                                          stats.hoursThisMonth.toStringAsFixed(1),
                                                        ),
                                                        _infoChip(
                                                          context,
                                                          'Estimated (month)',
                                                          stats.moneyText,
                                                        ),
                                                      ],
                                                    ),
                                                  ],
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Projects',
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Hourly rate and currency can be edited here (saved to employee workspace).',
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                if (workspaces.isEmpty)
                                  Card(
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Column(
                                        children: [
                                          Text(
                                            'No projects available for this access scope.',
                                            textAlign: TextAlign.center,
                                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          OutlinedButton.icon(
                                            onPressed: () => context.go('/employees'),
                                            icon: const Icon(Icons.arrow_back),
                                            label: const Text('Back to Employees'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  )
                                else
                                  ...workspaces.map((w) {
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 12),
                                      child: _ProjectCard(
                                        workspace: w,
                                        tracked: tr,
                                        firestore: widget.firestore,
                                        period: period,
                                        calc: calc,
                                        onBillingUpdated: _reloadWorkspaces,
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Future<_EmpHeaderStats> _loadHeaderStats(
    TrackedEmployee tr,
    ReportPeriod period,
    ReportCalculationService calc,
  ) async {
    final entries = await widget.firestore.fetchEntriesInRange(tr.employeeUid, period);
    final workspaces = await widget.firestore.fetchEmployeeWorkspaces(tr.employeeUid);
    final wsMap = {for (final w in workspaces) w.id: w};
    final filtered = entries.where((e) {
      if (e.isDeleted || e.end == null) return false;
      return wsMap[e.workspaceId]?.companySlug?.toLowerCase() == tr.companySlug.toLowerCase();
    }).toList();
    final hours = calc.hoursForEntries(filtered);
    final money = calc.estimatedAmountByCurrency(
      entries: filtered.where((e) => e.isWorkEntry).toList(),
      workspaceById: wsMap,
    );
    final moneyText = money.isEmpty ? '—' : money.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · ');
    return _EmpHeaderStats(hoursThisMonth: hours, moneyText: moneyText);
  }

  static Widget _infoChip(BuildContext context, String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _EmpHeaderStats {
  _EmpHeaderStats({required this.hoursThisMonth, required this.moneyText});

  final double hoursThisMonth;
  final String moneyText;
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.workspace,
    required this.tracked,
    required this.firestore,
    required this.period,
    required this.calc,
    required this.onBillingUpdated,
  });

  final ws.Workspace workspace;
  final TrackedEmployee tracked;
  final FirestoreService firestore;
  final ReportPeriod period;
  final ReportCalculationService calc;
  final VoidCallback onBillingUpdated;

  Color get _accent {
    final hex = workspace.colorHex;
    if (hex == null || hex.length < 7) return Colors.blueGrey;
    try {
      var h = hex.replaceFirst('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return Colors.blueGrey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<WorkEntry>>(
      future: firestore.fetchEntriesInRange(tracked.employeeUid, period),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Card(child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())));
        }
        final all = snap.data!;
        final scoped = all.where((e) => e.workspaceId == workspace.id && !e.isDeleted);
        final closed = scoped.where((e) => e.end != null).toList();
        var totalHours = 0.0;
        for (final e in closed) {
          final d = e.duration;
          if (d != null) totalHours += d.inMinutes / 60.0;
        }
        final split = calc.splitHours(closed);
        final billH = split.billableWorkHours;
        final nonBillH = split.nonBillableWorkHours;
        final money = calc.estimatedAmountByCurrency(
          entries: closed.where((e) => e.isWorkEntry).toList(),
          workspaceById: {workspace.id: workspace},
        );

        return Card(
          clipBehavior: Clip.antiAlias,
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 6, color: _accent),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                workspace.name,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                              ),
                            ),
                            if (workspace.isArchived)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: Chip(
                                  label: const Text('Archived'),
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 10,
                          runSpacing: 8,
                          children: [
                            _chip(
                              context,
                              'Rate',
                              workspace.hourlyRate != null
                                  ? '${workspace.hourlyRate!.toStringAsFixed(2)} ${workspace.currency ?? ''}'
                                  : 'Not set',
                            ),
                            _chip(context, 'Hours (month)', totalHours.toStringAsFixed(1)),
                            _chip(context, 'Billable h', billH.toStringAsFixed(1)),
                            _chip(context, 'Non-bill. h', nonBillH.toStringAsFixed(1)),
                            _chip(
                              context,
                              'Estimated',
                              money.isEmpty ? '—' : money.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · '),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton(
                              onPressed: () => context.go(
                                '/employees/detail/${tracked.id}/workspace/${workspace.id}/report',
                              ),
                              child: const Text('Open report'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () async {
                                await showEditWorkspaceBillingDialog(
                                  context,
                                  firestore: firestore,
                                  employeeUid: tracked.employeeUid,
                                  workspace: workspace,
                                );
                                onBillingUpdated();
                              },
                              icon: const Icon(Icons.edit_outlined, size: 18),
                              label: const Text('Edit rate'),
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
        );
      },
    );
  }

  static Widget _chip(BuildContext context, String label, String value) {
    return Chip(
      label: Text('$label: $value'),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}
