import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/email_domain_utils.dart';
import '../../core/utils/report_period.dart';
import '../../models/tracked_employee.dart';
import '../../models/workspace.dart';
import '../../services/firestore_service.dart';
import '../../services/report_calculation_service.dart';

class EmployeeDetailScreen extends StatelessWidget {
  const EmployeeDetailScreen({super.key, required this.firestore, required this.trackedId});

  final FirestoreService firestore;
  final String trackedId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final employerDomain = emailDomain(FirebaseAuth.instance.currentUser?.email ?? '');
    if (uid == null || employerDomain == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return StreamBuilder<List<TrackedEmployee>>(
      stream: firestore.trackedEmployeesStream(uid),
      builder: (context, snap) {
        final list = snap.data ?? [];
        TrackedEmployee? tracked;
        for (final t in list) {
          if (t.id == trackedId) tracked = t;
        }
        if (snap.connectionState == ConnectionState.waiting && tracked == null) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (tracked == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Employee')),
            body: const Center(child: Text('Employee not found on your list.')),
          );
        }

        final TrackedEmployee tr = tracked;

        return Scaffold(
          appBar: AppBar(
            title: Text(tr.displayName ?? tr.employeeEmail),
          ),
          body: FutureBuilder<List<Workspace>>(
            future: firestore.fetchEmployeeWorkspaces(tr.employeeUid),
            builder: (context, wsSnap) {
              if (!wsSnap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final workspaces = wsSnap.data!
                  .where((w) {
                    final slugOk = (w.companySlug ?? '').toLowerCase() == tr.companySlug.toLowerCase();
                    final dom = w.employeeWorkEmailDomain?.toLowerCase();
                    final domOk = dom != null && dom == employerDomain;
                    return slugOk && domOk && !w.isArchived;
                  })
                  .toList();

              final calc = ReportCalculationService();
              final period = monthContaining(DateTime.now());

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
                                Text(
                                  tr.displayName ?? tr.employeeEmail,
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 8),
                                Text(tr.employeeEmail),
                                const SizedBox(height: 4),
                                Text('Company: ${tr.companyName}'),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Projects (read-only)',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 12),
                        if (workspaces.isEmpty)
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'No matching workspaces for your access scope.',
                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
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
                                firestore: firestore,
                                period: period,
                                calc: calc,
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.workspace,
    required this.tracked,
    required this.firestore,
    required this.period,
    required this.calc,
  });

  final Workspace workspace;
  final TrackedEmployee tracked;
  final FirestoreService firestore;
  final ReportPeriod period;
  final ReportCalculationService calc;

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
    return FutureBuilder(
      future: firestore.fetchEntriesInRange(tracked.employeeUid, period),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Card(child: SizedBox(height: 120, child: Center(child: CircularProgressIndicator())));
        }
        final entries = snap.data!.where((e) => e.workspaceId == workspace.id && !e.isDeleted && e.end != null);
        final hours = calc.hoursForEntries(entries.toList());
        final money = calc.estimatedAmountByCurrency(
          entries: entries.where((e) => e.isWorkEntry).toList(),
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
                        Text(
                          workspace.name,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 12,
                          runSpacing: 8,
                          children: [
                            _chip(context, 'Rate', workspace.hourlyRate != null
                                ? '${workspace.hourlyRate!.toStringAsFixed(2)} ${workspace.currency ?? ''}'
                                : 'Not set'),
                            _chip(
                              context,
                              'Hours this month',
                              hours.toStringAsFixed(1),
                            ),
                            _chip(
                              context,
                              'Estimated',
                              money.isEmpty ? '—' : money.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · '),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: FilledButton(
                            onPressed: () => context.go(
                              '/employees/detail/${tracked.id}/workspace/${workspace.id}/report',
                            ),
                            child: const Text('View report'),
                          ),
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
