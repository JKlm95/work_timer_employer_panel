import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/report_period.dart';
import '../../models/employer_group.dart';
import '../../models/tracked_employee.dart';
import '../../services/firestore_service.dart';
import '../../services/report_calculation_service.dart';
import '../employees/widgets/add_employee_dialog.dart';
import '../groups/widgets/create_group_dialog.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.firestore});

  final FirestoreService firestore;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _calc = ReportCalculationService();

  Future<_MonthStats>? _statsFuture;
  String _trackedSig = '';

  ReportPeriod get _thisMonth => monthContaining(DateTime.now());

  void _ensureStats(List<TrackedEmployee> tracked) {
    final sig = tracked.map((t) => t.id).join('|');
    if (sig == _trackedSig && _statsFuture != null) return;
    _trackedSig = sig;
    _statsFuture = _loadMonthStats(tracked);
  }

  Future<_MonthStats> _loadMonthStats(List<TrackedEmployee> tracked) async {
    final period = _thisMonth;
    double totalHours = 0;
    final amountByCurrency = <String, double>{};
    for (final t in tracked) {
      final entries = await widget.firestore.fetchEntriesInRange(t.employeeUid, period);
      final workspaces = await widget.firestore.fetchEmployeeWorkspaces(t.employeeUid);
      final wsMap = {for (final w in workspaces) w.id: w};
      final filtered = entries.where((e) {
        if (e.isDeleted || e.end == null) return false;
        if (wsMap[e.workspaceId]?.companySlug?.toLowerCase() != t.companySlug.toLowerCase()) {
          return false;
        }
        return true;
      }).toList();
      totalHours += _calc.hoursForEntries(filtered);
      final money = _calc.estimatedAmountByCurrency(
        entries: filtered.where((e) => e.isWorkEntry).toList(),
        workspaceById: wsMap,
      );
      money.forEach((k, v) => amountByCurrency[k] = (amountByCurrency[k] ?? 0) + v);
    }
    return _MonthStats(totalHours: totalHours, amountByCurrency: amountByCurrency);
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Center(child: Text('Not signed in'));
    }

    return StreamBuilder<List<TrackedEmployee>>(
      stream: widget.firestore.trackedEmployeesStream(uid),
      builder: (context, trackedSnap) {
        return StreamBuilder<List<EmployerGroup>>(
          stream: widget.firestore.groupsStream(uid),
          builder: (context, groupsSnap) {
            final tracked = trackedSnap.data ?? [];
            final groupsCount = groupsSnap.data?.length ?? 0;

            if (trackedSnap.connectionState == ConnectionState.waiting && !trackedSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            _ensureStats(tracked);

            final statsFuture = _statsFuture ?? Future.value(const _MonthStats(totalHours: 0, amountByCurrency: {}));

            return SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1200),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'Dashboard',
                        style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Monthly work report overview — not a legal payroll document.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 24),
                      FutureBuilder<_MonthStats>(
                        future: statsFuture,
                        builder: (context, snap) {
                          final loading = snap.connectionState == ConnectionState.waiting;
                          final stats = snap.data ?? const _MonthStats(totalHours: 0, amountByCurrency: {});
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final w = constraints.maxWidth;
                              final cols = w > 1100 ? 4 : (w > 700 ? 2 : 1);
                              final cards = [
                                _SummaryCard(
                                  title: 'Tracked employees',
                                  value: '${tracked.length}',
                                  icon: Icons.people_outline,
                                  loading: false,
                                ),
                                _SummaryCard(
                                  title: 'Groups',
                                  value: '$groupsCount',
                                  icon: Icons.folder_special_outlined,
                                  loading: false,
                                ),
                                _SummaryCard(
                                  title: 'Hours this month',
                                  value: loading ? '…' : stats.totalHours.toStringAsFixed(1),
                                  icon: Icons.schedule,
                                  loading: loading,
                                ),
                                _SummaryCard(
                                  title: 'Estimated amount (month)',
                                  value: loading ? '…' : _formatMoney(stats.amountByCurrency),
                                  icon: Icons.payments_outlined,
                                  loading: loading,
                                  denseValue: true,
                                ),
                              ];
                              return Wrap(
                                spacing: 16,
                                runSpacing: 16,
                                children: [
                                  for (var i = 0; i < cards.length; i++)
                                    SizedBox(
                                      width: cols == 1
                                          ? w
                                          : (w - (cols - 1) * 16) / cols,
                                      child: cards[i],
                                    ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Text(
                            'Recent tracked employees',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const Spacer(),
                          FilledButton.tonalIcon(
                            onPressed: () => showAddEmployeeDialog(context, widget.firestore),
                            icon: const Icon(Icons.person_add_alt_1_outlined),
                            label: const Text('Add employee'),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton.icon(
                            onPressed: () => showCreateGroupDialog(context, widget.firestore),
                            icon: const Icon(Icons.create_new_folder_outlined),
                            label: const Text('Create group'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Card(
                        child: tracked.isEmpty
                            ? Padding(
                                padding: const EdgeInsets.all(32),
                                child: Center(
                                  child: Text(
                                    'No employees tracked yet. Add your first employee to start viewing reports.',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                              )
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: tracked.length.clamp(0, 5),
                                separatorBuilder: (context, _) => const Divider(height: 1),
                                itemBuilder: (context, i) {
                                  final e = tracked[i];
                                  return ListTile(
                                    leading: CircleAvatar(
                                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                      child: Text(_initial(e.displayName ?? e.employeeEmail)),
                                    ),
                                    title: Text(e.displayName ?? e.employeeEmail),
                                    subtitle: Text(e.companyName),
                                    trailing: Text(
                                      DateFormat.yMMMd().format(e.addedAt ?? DateTime.now()),
                                      style: Theme.of(context).textTheme.bodySmall,
                                    ),
                                    onTap: () => context.go('/employees/detail/${e.id}'),
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

  static String _initial(String s) {
    final t = s.trim();
    if (t.isEmpty) return '?';
    return t[0].toUpperCase();
  }

  static String _formatMoney(Map<String, double> m) {
    if (m.isEmpty) return '—';
    return m.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · ');
  }
}

class _MonthStats {
  const _MonthStats({required this.totalHours, required this.amountByCurrency});

  final double totalHours;
  final Map<String, double> amountByCurrency;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.loading,
    this.denseValue = false,
  });

  final String title;
  final String value;
  final IconData icon;
  final bool loading;
  final bool denseValue;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon, size: 36, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  loading
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(
                          value,
                          style: denseValue
                              ? Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)
                              : Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
