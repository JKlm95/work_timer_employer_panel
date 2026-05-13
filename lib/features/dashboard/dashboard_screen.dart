import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/utils/employee_name_utils.dart';
import '../../core/utils/live_running_amounts.dart';
import '../../core/utils/report_period.dart';
import '../../core/widgets/employee_presence_badge.dart';
import '../../models/employee_live_status.dart';
import '../../models/employer_group.dart';
import '../../models/tracked_employee.dart';
import '../../models/workspace.dart';
import '../../services/firestore_service.dart';
import '../../services/report_calculation_service.dart';
import '../employees/widgets/add_employee_dialog.dart';
import '../groups/widgets/create_group_dialog.dart';
import 'dashboard_live_status_host.dart';

class _DashboardStreamError extends StatelessWidget {
  const _DashboardStreamError({required this.title, required this.detail});

  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_outlined, size: 48, color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SelectableText(
                detail,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

int _countWorkingNow(List<TrackedEmployee> tracked, Map<String, EmployeeLiveStatus?> live) {
  final seen = <String>{};
  var n = 0;
  for (final t in tracked) {
    final uid = t.employeeUid;
    if (uid.isEmpty || seen.contains(uid)) continue;
    final l = live[uid];
    if (l != null && l.timerStateLower == 'running') {
      seen.add(uid);
      n++;
    }
  }
  return n;
}

enum _DashboardStatsRefreshReason { initial, manual, auto, trackedChanged }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.firestore});

  final FirestoreService firestore;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _calc = ReportCalculationService();

  Future<_DashboardSnapshot>? _statsFuture;
  String _statsSig = '';
  int _refreshNonce = 0;
  bool _refreshingStats = false;
  DateTime? _lastStatsRefresh;
  Timer? _autoStatsTimer;
  List<TrackedEmployee> _latestTracked = [];

  /// Avoid calling [setState] during [build] (tracked StreamBuilder); schedule sync after frame.
  List<TrackedEmployee> _pendingStatsTracked = [];
  bool _statsPostFrameScheduled = false;

  bool _hadFirstStatsPostFrame = false;
  String _lastStatsTrackedIdsPostFrame = '';

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _monthEntrySubs = [];
  String _monthEntryListenUidSig = '';
  Timer? _entriesDebounceTimer;

  @override
  void initState() {
    super.initState();
    _autoStatsTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      setState(() {
        _refreshNonce++;
        _statsSig = '';
      });
      _syncStatsIfNeeded(_latestTracked, reason: _DashboardStatsRefreshReason.auto);
    });
  }

  @override
  void dispose() {
    _autoStatsTimer?.cancel();
    _entriesDebounceTimer?.cancel();
    for (final s in _monthEntrySubs) {
      s.cancel();
    }
    _monthEntrySubs.clear();
    super.dispose();
  }

  ReportPeriod get _thisMonth => monthContaining(DateTime.now());

  void _onPostFrameSyncStats(Duration _) {
    _statsPostFrameScheduled = false;
    if (!mounted) return;
    final tracked = _pendingStatsTracked;
    _ensureMonthEntryListeners(tracked);
    final reason = _postFrameStatsReason(tracked);
    _syncStatsIfNeeded(tracked, reason: reason);
  }

  /// Do not call from [build] synchronously — it ends in [setState]. Use post-frame scheduling.
  void _requestDashboardStatsSync(List<TrackedEmployee> tracked) {
    _pendingStatsTracked = List<TrackedEmployee>.from(tracked);
    if (_statsPostFrameScheduled) return;
    _statsPostFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback(_onPostFrameSyncStats);
  }

  _DashboardStatsRefreshReason _postFrameStatsReason(List<TrackedEmployee> tracked) {
    final idKey = tracked.isEmpty ? '__empty__' : tracked.map((e) => e.id).join('|');
    final _DashboardStatsRefreshReason r;
    if (!_hadFirstStatsPostFrame) {
      _hadFirstStatsPostFrame = true;
      r = _DashboardStatsRefreshReason.initial;
    } else if (idKey != _lastStatsTrackedIdsPostFrame) {
      r = _DashboardStatsRefreshReason.trackedChanged;
    } else {
      r = _DashboardStatsRefreshReason.trackedChanged;
    }
    _lastStatsTrackedIdsPostFrame = idKey;
    return r;
  }

  void _ensureMonthEntryListeners(List<TrackedEmployee> tracked) {
    final period = _thisMonth;
    final monthKey = '${period.start.year}-${period.start.month.toString().padLeft(2, '0')}';
    final uids = tracked.map((e) => e.employeeUid).where((u) => u.trim().isNotEmpty).toSet().toList()..sort();
    final sig = '$monthKey|${uids.join('|')}';
    if (sig == _monthEntryListenUidSig) return;
    _monthEntryListenUidSig = sig;
    _entriesDebounceTimer?.cancel();
    for (final s in _monthEntrySubs) {
      s.cancel();
    }
    _monthEntrySubs.clear();
    if (uids.isEmpty) return;
    for (final uid in uids) {
      final sub = widget.firestore.entriesInMonthSnapshots(uid, period).skip(1).listen((_) {
        _scheduleStatsReloadFromFirestoreEntries();
      });
      _monthEntrySubs.add(sub);
    }
  }

  void _scheduleStatsReloadFromFirestoreEntries() {
    if (!mounted) return;
    _entriesDebounceTimer?.cancel();
    _entriesDebounceTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      setState(() {
        _refreshNonce++;
        _statsSig = '';
      });
      _syncStatsIfNeeded(_latestTracked, reason: _DashboardStatsRefreshReason.auto);
    });
  }

  void _logStatsRefreshDebug(
    _DashboardStatsRefreshReason reason,
    List<TrackedEmployee> tracked,
    Map<String, double> amountByCurrency,
  ) {
    if (!kDebugMode) return;
    final sumNaive = amountByCurrency.values.fold<double>(0, (a, b) => a + b);
    debugPrint(
      '[Dashboard] stats refreshed reason=${reason.name} refreshNonce=$_refreshNonce '
      'employees=${tracked.length} estimatedByCurrency=$amountByCurrency totalNaiveSum=${sumNaive.toStringAsFixed(2)}',
    );
  }

  void _syncStatsIfNeeded(List<TrackedEmployee> tracked, {required _DashboardStatsRefreshReason reason}) {
    _latestTracked = tracked;
    if (tracked.isEmpty) {
      final sig = 'empty|$_refreshNonce';
      if (_statsSig == sig && _statsFuture != null) return;
      _statsSig = sig;
      _statsFuture = Future.value(_DashboardSnapshot.empty());
      _logStatsRefreshDebug(reason, tracked, {});
      if (mounted) setState(() {});
      return;
    }
    final sig = '${tracked.map((e) => e.id).join('|')}|$_refreshNonce';
    if (_statsSig == sig && _statsFuture != null) return;
    _statsSig = sig;
    _statsFuture = _loadDashboardSnapshot(tracked, reason);
    if (mounted) setState(() {});
  }

  Future<void> _manualRefresh(List<TrackedEmployee> tracked) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    setState(() => _refreshingStats = true);
    try {
      await widget.firestore.ensureTrackedEmployeeUidAccessDocs(uid);
      setState(() {
        _refreshNonce++;
        _statsSig = '';
      });
      _syncStatsIfNeeded(tracked, reason: _DashboardStatsRefreshReason.manual);
      final f = _statsFuture;
      if (f != null) await f;
      if (mounted) setState(() => _lastStatsRefresh = DateTime.now());
    } finally {
      if (mounted) setState(() => _refreshingStats = false);
    }
  }

  Future<_DashboardSnapshot> _loadDashboardSnapshot(
    List<TrackedEmployee> tracked,
    _DashboardStatsRefreshReason reason,
  ) async {
    try {
      const preferServer = true;
      final period = _thisMonth;
      double totalHours = 0;
      final amountByCurrency = <String, double>{};
      final lastByTracked = <String, DateTime?>{};
      final workspaceMapsByEmployeeUid = <String, Map<String, Workspace>>{};

      final lastTimes = await Future.wait(
        tracked.map((t) => widget.firestore.fetchLastActivityAt(t.employeeUid, preferServer: preferServer)),
      );
      for (var i = 0; i < tracked.length; i++) {
        lastByTracked[tracked[i].id] = lastTimes[i];
      }

      for (final t in tracked) {
        final entries = await widget.firestore.fetchEntriesInRange(
          t.employeeUid,
          period,
          preferServer: preferServer,
        );
        final workspaces = await widget.firestore.fetchEmployeeWorkspaces(
          t.employeeUid,
          preferServer: preferServer,
        );
        final wsMap = {for (final w in workspaces) w.id: w};
        workspaceMapsByEmployeeUid[t.employeeUid] = wsMap;
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

      _logStatsRefreshDebug(reason, tracked, amountByCurrency);

      return _DashboardSnapshot(
        totalHours: totalHours,
        amountByCurrency: amountByCurrency,
        lastActivityByTrackedId: lastByTracked,
        workspaceMapsByEmployeeUid: workspaceMapsByEmployeeUid,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Dashboard] _loadDashboardSnapshot failed: $e');
        debugPrintStack(stackTrace: st, label: 'dashboard_stats');
      }
      return _DashboardSnapshot.empty();
    }
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
            if (trackedSnap.hasError) {
              if (kDebugMode) {
                debugPrint('[Dashboard] trackedEmployeesStream error: ${trackedSnap.error}');
              }
              return _DashboardStreamError(
                title: 'Could not load employees',
                detail: '${trackedSnap.error}',
              );
            }
            if (groupsSnap.hasError) {
              if (kDebugMode) {
                debugPrint('[Dashboard] groupsStream error: ${groupsSnap.error}');
              }
              return _DashboardStreamError(
                title: 'Could not load groups',
                detail: '${groupsSnap.error}',
              );
            }

            final tracked = trackedSnap.data ?? [];
            final groupsCount = groupsSnap.data?.length ?? 0;

            if (trackedSnap.connectionState == ConnectionState.waiting && !trackedSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }

            _requestDashboardStatsSync(tracked);

            final statsFuture = _statsFuture ??
                Future.value(_DashboardSnapshot.empty());

            return DashboardLiveStatusHost(
              tracked: tracked,
              firestore: widget.firestore,
              builder: (context, liveByUid) {
                try {
                  final workingNow = _countWorkingNow(tracked, liveByUid);
                  return SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1200),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
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
                                  ],
                                ),
                              ),
                              IconButton(
                                tooltip: 'Refresh data',
                                onPressed: _refreshingStats || tracked.isEmpty ? null : () => _manualRefresh(tracked),
                                icon: _refreshingStats
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.refresh),
                              ),
                              if (_lastStatsRefresh != null)
                                Padding(
                                  padding: const EdgeInsets.only(left: 8, top: 12),
                                  child: Text(
                                    'Last updated: ${DateFormat.Hms().format(_lastStatsRefresh!)}',
                                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 24),
                          FutureBuilder<_DashboardSnapshot>(
                            key: ValueKey<(int, String)>((_refreshNonce, _statsSig)),
                            future: statsFuture,
                            builder: (context, snap) {
                              if (snap.hasError) {
                                if (kDebugMode) {
                                  debugPrint('[Dashboard] FutureBuilder stats error: ${snap.error}');
                                  final st = snap.stackTrace;
                                  if (st != null) debugPrintStack(stackTrace: st, label: 'dashboard_stats_future');
                                }
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Could not load monthly stats.',
                                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                                      ),
                                      const SizedBox(height: 8),
                                      SelectableText(
                                        '${snap.error}',
                                        style: Theme.of(context).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                );
                              }
                              final loading = snap.connectionState == ConnectionState.waiting;
                              final stats = snap.data ?? _DashboardSnapshot.empty();
                              LiveRunningMoneySummary liveSummary;
                              try {
                                liveSummary = computeLiveRunningMoneySummary(
                                  tracked: tracked,
                                  liveByEmployeeUid: liveByUid,
                                  workspaceMapsByEmployeeUid: stats.workspaceMapsByEmployeeUid,
                                  at: DateTime.now(),
                                );
                              } catch (e, st) {
                                if (kDebugMode) {
                                  debugPrint('[Dashboard] live amount compute failed: $e');
                                  debugPrintStack(stackTrace: st, label: 'dashboard_live_amount');
                                }
                                liveSummary = LiveRunningMoneySummary(
                                  byCurrency: {},
                                  hasRunningWithoutRate: false,
                                );
                              }
                              return LayoutBuilder(
                                builder: (context, constraints) {
                                  final w = constraints.maxWidth;
                                  final cards = [
                                    _SummaryCard(
                                      title: 'Tracked employees',
                                      value: '${tracked.length}',
                                      icon: Icons.people_outline,
                                      loading: false,
                                    ),
                                    _SummaryCard(
                                      title: 'Active groups',
                                      value: '$groupsCount',
                                      icon: Icons.folder_special_outlined,
                                      loading: false,
                                    ),
                                    _SummaryCard(
                                      title: 'Working now',
                                      value: '$workingNow',
                                      icon: Icons.play_circle_outline,
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
                                      subtitle: 'From saved entries',
                                      value: loading ? '…' : _formatMoney(stats.amountByCurrency),
                                      icon: Icons.payments_outlined,
                                      loading: loading,
                                      denseValue: true,
                                    ),
                                    _SummaryCard(
                                      title: 'Live running (est.)',
                                      subtitle: 'UI only — not saved',
                                      value: loading ? '…' : liveSummary.displayValue(),
                                      icon: Icons.bolt_outlined,
                                      loading: loading,
                                      denseValue: true,
                                    ),
                                  ];
                                  final cols = w > 1100 ? 3 : (w > 520 ? 2 : 1);
                                  return Wrap(
                                    spacing: 16,
                                    runSpacing: 16,
                                    children: [
                                      for (var i = 0; i < cards.length; i++)
                                        SizedBox(
                                          width: cols == 1 ? w : (w - (cols - 1) * 16) / cols,
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
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                onPressed: () => context.go('/payroll'),
                                icon: const Icon(Icons.payments_outlined),
                                label: const Text('Payroll report'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Card(
                            child: tracked.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(32),
                                    child: Column(
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
                                          'Add your first employee to start viewing reports.',
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 20),
                                        FilledButton.icon(
                                          onPressed: () => showAddEmployeeDialog(context, widget.firestore),
                                          icon: const Icon(Icons.person_add_alt_1_outlined),
                                          label: const Text('Add employee'),
                                        ),
                                      ],
                                    ),
                                  )
                                : FutureBuilder<_DashboardSnapshot>(
                                    key: ValueKey<(int, String)>((_refreshNonce, _statsSig)),
                                    future: statsFuture,
                                    builder: (context, snap) {
                                      if (snap.hasError) {
                                        if (kDebugMode) {
                                          debugPrint('[Dashboard] recent list stats error: ${snap.error}');
                                          final st = snap.stackTrace;
                                          if (st != null) {
                                            debugPrintStack(stackTrace: st, label: 'dashboard_recent_list');
                                          }
                                        }
                                        return Padding(
                                          padding: const EdgeInsets.all(16),
                                          child: Text(
                                            'Could not load activity for this list.',
                                            style: TextStyle(color: Theme.of(context).colorScheme.error),
                                          ),
                                        );
                                      }
                                      final st = snap.data;
                                      return ListView.separated(
                                        shrinkWrap: true,
                                        physics: const NeverScrollableScrollPhysics(),
                                        itemCount: tracked.length.clamp(0, 5),
                                        separatorBuilder: (context, _) => const Divider(height: 1),
                                        itemBuilder: (context, i) {
                                          final e = tracked[i];
                                          final last = st?.lastActivityByTrackedId[e.id];
                                          final lastText = last == null
                                              ? 'Last activity: —'
                                              : 'Last activity: ${DateFormat.yMMMd().add_jm().format(last)}';
                                          return ListTile(
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            leading: CircleAvatar(
                                              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                              child: Text(employeeInitials(e)),
                                            ),
                                            title: Text(employeeFullName(e)),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (employeeShowEmailAsSubtitle(e))
                                                  Text(e.employeeEmail, maxLines: 1, overflow: TextOverflow.ellipsis),
                                                Text(e.companyName, maxLines: 1, overflow: TextOverflow.ellipsis),
                                                const SizedBox(height: 4),
                                                Text(
                                                  lastText,
                                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            trailing: EmployeePresenceBadge(
                                              firestore: widget.firestore,
                                              tracked: e,
                                              compact: true,
                                            ),
                                            onTap: () => context.go('/employees/detail/${e.id}'),
                                          );
                                        },
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
                } catch (e, st) {
                  if (kDebugMode) {
                    debugPrint('[Dashboard] live host builder failed: $e');
                    debugPrintStack(stackTrace: st, label: 'dashboard_live_host_builder');
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Dashboard layout error. Pull to refresh or use Refresh data.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Theme.of(context).colorScheme.error),
                      ),
                    ),
                  );
                }
              },
            );
          },
        );
      },
    );
  }

  static String _formatMoney(Map<String, double> m) {
    if (m.isEmpty) return '—';
    return m.entries.map((e) => '${e.key} ${e.value.toStringAsFixed(2)}').join(' · ');
  }
}

class _DashboardSnapshot {
  _DashboardSnapshot({
    required this.totalHours,
    required this.amountByCurrency,
    required this.lastActivityByTrackedId,
    required this.workspaceMapsByEmployeeUid,
  });

  factory _DashboardSnapshot.empty() => _DashboardSnapshot(
    totalHours: 0,
    amountByCurrency: {},
    lastActivityByTrackedId: {},
    workspaceMapsByEmployeeUid: {},
  );

  final double totalHours;
  final Map<String, double> amountByCurrency;
  final Map<String, DateTime?> lastActivityByTrackedId;
  final Map<String, Map<String, Workspace>> workspaceMapsByEmployeeUid;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.loading,
    this.denseValue = false,
    this.subtitle,
  });

  final String title;
  final String value;
  final IconData icon;
  final bool loading;
  final bool denseValue;
  final String? subtitle;

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
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                  ],
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
