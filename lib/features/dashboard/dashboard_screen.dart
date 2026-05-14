import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_layout.dart';
import '../../core/utils/employee_name_utils.dart';
import '../../core/utils/live_running_amounts.dart';
import '../../core/utils/report_period.dart';
import '../../core/widgets/app_empty_state.dart';
import '../../core/widgets/app_pulse_loading.dart';
import '../../core/widgets/employee_avatar.dart';
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
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppLayout.pagePadding),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(AppLayout.cardPadding),
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
      ),
    );
  }
}

int _countWorkingNow(
  List<TrackedEmployee> tracked,
  Map<String, EmployeeLiveStatus?> live,
) {
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

  final List<StreamSubscription<void>> _monthEntrySubs = [];
  String _monthEntryListenUidSig = '';
  Timer? _entriesDebounceTimer;

  /// Last successful stats snapshot (avoids flicker when auto-refresh replaces [Future]).
  _DashboardSnapshot? _statsDisplayCache;

  @override
  void initState() {
    super.initState();
    _autoStatsTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      setState(() {
        _refreshNonce++;
        _statsSig = '';
      });
      _syncStatsIfNeeded(
        _latestTracked,
        reason: _DashboardStatsRefreshReason.auto,
      );
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
    final employerUid = FirebaseAuth.instance.currentUser?.uid;
    if (employerUid != null) {
      _ensureMonthEntryListeners(tracked, employerUid);
    }
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

  _DashboardStatsRefreshReason _postFrameStatsReason(
    List<TrackedEmployee> tracked,
  ) {
    final idKey = tracked.isEmpty
        ? '__empty__'
        : tracked.map((e) => e.id).join('|');
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

  void _ensureMonthEntryListeners(
    List<TrackedEmployee> tracked,
    String employerUid,
  ) {
    final period = _thisMonth;
    final monthKey =
        '${period.start.year}-${period.start.month.toString().padLeft(2, '0')}';
    final uids =
        tracked
            .map((e) => e.employeeUid)
            .where((u) => u.trim().isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final sig = '$monthKey|$employerUid|${uids.join('|')}';
    if (sig == _monthEntryListenUidSig) return;
    _monthEntryListenUidSig = sig;
    _entriesDebounceTimer?.cancel();
    for (final s in _monthEntrySubs) {
      s.cancel();
    }
    _monthEntrySubs.clear();
    if (uids.isEmpty) return;
    for (final uid in uids) {
      final sub = widget.firestore
          .entriesMonthTouchSignalsForEmployer(employerUid, uid, period)
          .skip(1)
          .listen((_) {
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
      _syncStatsIfNeeded(
        _latestTracked,
        reason: _DashboardStatsRefreshReason.auto,
      );
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

  void _syncStatsIfNeeded(
    List<TrackedEmployee> tracked, {
    required _DashboardStatsRefreshReason reason,
  }) {
    _latestTracked = tracked;
    if (tracked.isEmpty) {
      final sig = 'empty|$_refreshNonce';
      if (_statsSig == sig && _statsFuture != null) return;
      _statsSig = sig;
      final emptySnap = _DashboardSnapshot.empty();
      _statsFuture = Future.value(emptySnap);
      _logStatsRefreshDebug(reason, tracked, {});
      if (mounted) {
        setState(() {
          _statsDisplayCache = emptySnap;
          _lastStatsRefresh = DateTime.now();
        });
      }
      return;
    }
    final sig = '${tracked.map((e) => e.id).join('|')}|$_refreshNonce';
    if (_statsSig == sig && _statsFuture != null) return;
    _statsSig = sig;
    _statsFuture = _loadDashboardSnapshot(tracked, reason).then((v) {
      if (mounted) {
        setState(() {
          _statsDisplayCache = v;
          _lastStatsRefresh = DateTime.now();
        });
      }
      return v;
    });
    if (mounted) setState(() {});
  }

  _DashboardSnapshot _statsSnapshotForUi(
    AsyncSnapshot<_DashboardSnapshot> snap,
  ) {
    if (snap.hasData) return snap.data!;
    if (_statsDisplayCache != null) return _statsDisplayCache!;
    return _DashboardSnapshot.empty();
  }

  /// Spinner on monthly aggregates only before we ever loaded stats (no flicker on refresh).
  bool _statsFirstLoadSpinner(AsyncSnapshot<_DashboardSnapshot> snap) {
    return !snap.hasError &&
        snap.connectionState == ConnectionState.waiting &&
        !snap.hasData &&
        _statsDisplayCache == null;
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
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[Dashboard] manual refresh failed: $e');
        debugPrintStack(stackTrace: st, label: 'dashboard_manual_refresh');
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Could not refresh data: $e')));
      }
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
      final employerUid = FirebaseAuth.instance.currentUser?.uid;
      if (employerUid == null) {
        return _DashboardSnapshot.empty();
      }
      double totalHours = 0;
      final amountByCurrency = <String, double>{};
      final lastByTracked = <String, DateTime?>{};
      final workspaceMapsByEmployeeUid = <String, Map<String, Workspace>>{};

      final lastTimes = await Future.wait(
        tracked.map(
          (t) => widget.firestore.fetchLastActivityAtForEmployer(
            employerUid,
            t.employeeUid,
            preferServer: preferServer,
          ),
        ),
      );
      for (var i = 0; i < tracked.length; i++) {
        lastByTracked[tracked[i].id] = lastTimes[i];
      }

      for (final t in tracked) {
        final entries = await widget.firestore.fetchEntriesInRangeForEmployer(
          employerUid,
          t.employeeUid,
          period,
          preferServer: preferServer,
        );
        final workspaces = await widget.firestore
            .fetchEmployeeWorkspacesForEmployer(
              employerUid,
              t.employeeUid,
              preferServer: preferServer,
            );
        final wsMap = {for (final w in workspaces) w.id: w};
        workspaceMapsByEmployeeUid[t.employeeUid] = wsMap;
        final filtered = entries.where((e) {
          if (e.isDeleted || e.end == null) return false;
          if (wsMap[e.workspaceId] == null) return false;
          return true;
        }).toList();
        totalHours += _calc.hoursForEntries(filtered);
        final money = _calc.estimatedAmountByCurrency(
          entries: filtered.where((e) => e.isWorkEntry).toList(),
          workspaceById: wsMap,
        );
        money.forEach(
          (k, v) => amountByCurrency[k] = (amountByCurrency[k] ?? 0) + v,
        );
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
                debugPrint(
                  '[Dashboard] trackedEmployeesStream error: ${trackedSnap.error}',
                );
              }
              return _DashboardStreamError(
                title: 'Could not load employees',
                detail: '${trackedSnap.error}',
              );
            }
            if (groupsSnap.hasError) {
              if (kDebugMode) {
                debugPrint(
                  '[Dashboard] groupsStream error: ${groupsSnap.error}',
                );
              }
              return _DashboardStreamError(
                title: 'Could not load groups',
                detail: '${groupsSnap.error}',
              );
            }

            final tracked = trackedSnap.data ?? [];
            final groupsCount = groupsSnap.data?.length ?? 0;

            if (trackedSnap.connectionState == ConnectionState.waiting &&
                !trackedSnap.hasData) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(AppLayout.pagePadding),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 360),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const AppPulseLoading(rows: 5),
                        const SizedBox(height: 20),
                        Text(
                          'Loading dashboard…',
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

            _requestDashboardStatsSync(tracked);

            final statsFuture =
                _statsFuture ?? Future.value(_DashboardSnapshot.empty());

            return DashboardLiveStatusHost(
              tracked: tracked,
              firestore: widget.firestore,
              builder: (context, liveByUid) {
                try {
                  final workingNow = _countWorkingNow(tracked, liveByUid);
                  return SingleChildScrollView(
                    padding: const EdgeInsets.all(AppLayout.pagePadding),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1200),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Dashboard',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -0.5,
                                  ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Monthly work report overview — not a legal payroll document.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                            ),
                            const SizedBox(height: 18),
                            Material(
                              color: Theme.of(context).colorScheme.surface,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppLayout.radiusMd,
                                ),
                                side: BorderSide(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .outlineVariant
                                      .withValues(alpha: 0.75),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                child: LayoutBuilder(
                                  builder: (context, c) {
                                    final narrow = c.maxWidth < 520;
                                    if (narrow) {
                                      return Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          Text(
                                            'Data refresh',
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelLarge
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _lastStatsRefresh == null
                                                ? 'Last updated: —'
                                                : 'Last updated: ${DateFormat.Hms().format(_lastStatsRefresh!)}',
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: Theme.of(context)
                                                      .colorScheme
                                                      .onSurfaceVariant,
                                                ),
                                          ),
                                          const SizedBox(height: 8),
                                          Align(
                                            alignment: Alignment.centerRight,
                                            child: IconButton.filledTonal(
                                              tooltip: 'Refresh data',
                                              onPressed:
                                                  _refreshingStats ||
                                                      tracked.isEmpty
                                                  ? null
                                                  : () =>
                                                        _manualRefresh(tracked),
                                              icon: _refreshingStats
                                                  ? const SizedBox(
                                                      width: 22,
                                                      height: 22,
                                                      child:
                                                          CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                          ),
                                                    )
                                                  : const Icon(Icons.refresh),
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    return Row(
                                      children: [
                                        Text(
                                          'Data refresh',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelLarge
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const Spacer(),
                                        Text(
                                          _lastStatsRefresh == null
                                              ? 'Last updated: —'
                                              : 'Last updated: ${DateFormat.Hms().format(_lastStatsRefresh!)}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: Theme.of(
                                                  context,
                                                ).colorScheme.onSurfaceVariant,
                                              ),
                                        ),
                                        const SizedBox(width: 8),
                                        IconButton.filledTonal(
                                          tooltip: 'Refresh data',
                                          onPressed:
                                              _refreshingStats ||
                                                  tracked.isEmpty
                                              ? null
                                              : () => _manualRefresh(tracked),
                                          icon: _refreshingStats
                                              ? const SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(Icons.refresh),
                                        ),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: AppLayout.sectionGap),
                            FutureBuilder<_DashboardSnapshot>(
                              key: ValueKey<(int, String)>((
                                _refreshNonce,
                                _statsSig,
                              )),
                              future: statsFuture,
                              builder: (context, snap) {
                                if (snap.hasError) {
                                  if (kDebugMode) {
                                    debugPrint(
                                      '[Dashboard] FutureBuilder stats error: ${snap.error}',
                                    );
                                    final st = snap.stackTrace;
                                    if (st != null) {
                                      debugPrintStack(
                                        stackTrace: st,
                                        label: 'dashboard_stats_future',
                                      );
                                    }
                                  }
                                }
                                final stats = _statsSnapshotForUi(snap);
                                final monthLoading = _statsFirstLoadSpinner(
                                  snap,
                                );
                                final gate = <String, Set<String>>{
                                  for (final t in tracked)
                                    if (t.employeeUid.trim().isNotEmpty)
                                      t.employeeUid.trim():
                                          stats
                                              .workspaceMapsByEmployeeUid[t
                                                  .employeeUid
                                                  .trim()]
                                              ?.keys
                                              .toSet() ??
                                          {},
                                };
                                LiveRunningMoneySummary liveSummary;
                                try {
                                  liveSummary = computeLiveRunningMoneySummary(
                                    tracked: tracked,
                                    liveByEmployeeUid: liveByUid,
                                    workspaceMapsByEmployeeUid:
                                        stats.workspaceMapsByEmployeeUid,
                                    at: DateTime.now(),
                                    allowedWorkspaceIdsByEmployeeUid: gate,
                                  );
                                } catch (e, st) {
                                  if (kDebugMode) {
                                    debugPrint(
                                      '[Dashboard] live amount compute failed: $e',
                                    );
                                    debugPrintStack(
                                      stackTrace: st,
                                      label: 'dashboard_live_amount',
                                    );
                                  }
                                  liveSummary = LiveRunningMoneySummary(
                                    byCurrency: {},
                                    hasRunningWithoutRate: false,
                                  );
                                }
                                final scheme = Theme.of(context).colorScheme;
                                final errorBanner = snap.hasError
                                    ? Material(
                                        color: scheme.errorContainer.withValues(
                                          alpha: 0.5,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Icon(
                                                    Icons.warning_amber_rounded,
                                                    color:
                                                        scheme.onErrorContainer,
                                                    size: 22,
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Expanded(
                                                    child: Text(
                                                      'Monthly stats could not be refreshed. Showing last loaded values below.',
                                                      style: Theme.of(context)
                                                          .textTheme
                                                          .bodySmall
                                                          ?.copyWith(
                                                            color: scheme
                                                                .onErrorContainer,
                                                          ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              SelectableText(
                                                '${snap.error}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: scheme
                                                          .onErrorContainer,
                                                    ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      )
                                    : null;

                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (errorBanner != null) ...[
                                      errorBanner,
                                      const SizedBox(height: 12),
                                    ],
                                    LayoutBuilder(
                                      builder: (context, constraints) {
                                        final w = constraints.maxWidth;
                                        final cards = [
                                          _SummaryCard(
                                            title: 'Hours this month',
                                            value: monthLoading
                                                ? '…'
                                                : stats.totalHours
                                                      .toStringAsFixed(1),
                                            icon: Icons.schedule_rounded,
                                            loading: monthLoading,
                                          ),
                                          _SummaryCard(
                                            title: 'Estimated amount (month)',
                                            subtitle:
                                                'Closed entries · saved in Firestore · this month',
                                            value: monthLoading
                                                ? '…'
                                                : _formatMoney(
                                                    stats.amountByCurrency,
                                                  ),
                                            icon: Icons.payments_outlined,
                                            loading: monthLoading,
                                            denseValue: true,
                                          ),
                                          _SummaryCard(
                                            title: 'Live running (est.)',
                                            subtitle:
                                                'Running timers × rate · UI only, not saved',
                                            value: liveSummary.displayValue(),
                                            icon: Icons.bolt_rounded,
                                            loading: false,
                                            denseValue: true,
                                          ),
                                          _SummaryCard(
                                            title: 'Tracked employees',
                                            value: '${tracked.length}',
                                            icon: Icons.people_outline_rounded,
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
                                            icon: Icons.play_circle_rounded,
                                            loading: false,
                                          ),
                                        ];
                                        final cols = w > 1100
                                            ? 3
                                            : (w > 520 ? 2 : 1);
                                        return Wrap(
                                          spacing: 16,
                                          runSpacing: 16,
                                          children: [
                                            for (
                                              var i = 0;
                                              i < cards.length;
                                              i++
                                            )
                                              SizedBox(
                                                width: cols == 1
                                                    ? w
                                                    : (w - (cols - 1) * 16) /
                                                          cols,
                                                child: cards[i],
                                              ),
                                          ],
                                        );
                                      },
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: AppLayout.sectionGap),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Recent tracked employees',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Up to five people — open a profile for full timesheet.',
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
                                const Spacer(),
                                FilledButton.tonalIcon(
                                  onPressed: () => showAddEmployeeDialog(
                                    context,
                                    widget.firestore,
                                  ),
                                  icon: const Icon(
                                    Icons.person_add_alt_1_outlined,
                                  ),
                                  label: const Text('Add employee'),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton.icon(
                                  onPressed: () => showCreateGroupDialog(
                                    context,
                                    widget.firestore,
                                  ),
                                  icon: const Icon(
                                    Icons.create_new_folder_outlined,
                                  ),
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
                                  ? AppEmptyState(
                                      icon: Icons.group_add_outlined,
                                      title: 'No employees tracked yet',
                                      subtitle:
                                          'Add your first employee to start viewing reports and live presence.',
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
                                    )
                                  : FutureBuilder<_DashboardSnapshot>(
                                      key: ValueKey<(int, String)>((
                                        _refreshNonce,
                                        _statsSig,
                                      )),
                                      future: statsFuture,
                                      builder: (context, snap) {
                                        if (snap.hasError) {
                                          if (kDebugMode) {
                                            debugPrint(
                                              '[Dashboard] recent list stats error: ${snap.error}',
                                            );
                                            final st = snap.stackTrace;
                                            if (st != null) {
                                              debugPrintStack(
                                                stackTrace: st,
                                                label: 'dashboard_recent_list',
                                              );
                                            }
                                          }
                                        }
                                        final st = _statsSnapshotForUi(snap);
                                        return Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.stretch,
                                          children: [
                                            if (snap.hasError)
                                              Padding(
                                                padding:
                                                    const EdgeInsets.fromLTRB(
                                                      16,
                                                      12,
                                                      16,
                                                      0,
                                                    ),
                                                child: Text(
                                                  'Activity times may be outdated (stats refresh failed).',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: Theme.of(
                                                          context,
                                                        ).colorScheme.error,
                                                      ),
                                                ),
                                              ),
                                            ListView.separated(
                                              shrinkWrap: true,
                                              physics:
                                                  const NeverScrollableScrollPhysics(),
                                              itemCount: tracked.length.clamp(
                                                0,
                                                5,
                                              ),
                                              separatorBuilder: (context, _) =>
                                                  const Divider(height: 1),
                                              itemBuilder: (context, i) {
                                                final e = tracked[i];
                                                final last =
                                                    st.lastActivityByTrackedId[e
                                                        .id];
                                                final lastText = last == null
                                                    ? 'Last activity: —'
                                                    : 'Last activity: ${DateFormat.yMMMd().add_jm().format(last)}';
                                                return ListTile(
                                                  contentPadding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 16,
                                                        vertical: 8,
                                                      ),
                                                  leading: EmployeeAvatar(
                                                    seed: e.employeeUid,
                                                    initials: employeeInitials(
                                                      e,
                                                    ),
                                                    radius: 22,
                                                  ),
                                                  title: Text(
                                                    employeeFullName(e),
                                                  ),
                                                  subtitle: Column(
                                                    crossAxisAlignment:
                                                        CrossAxisAlignment
                                                            .start,
                                                    children: [
                                                      if (employeeShowEmailAsSubtitle(
                                                        e,
                                                      ))
                                                        Text(
                                                          e.employeeEmail,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                        ),
                                                      Text(
                                                        e.companyName,
                                                        maxLines: 1,
                                                        overflow: TextOverflow
                                                            .ellipsis,
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        lastText,
                                                        style: Theme.of(context)
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color: Theme.of(context)
                                                                  .colorScheme
                                                                  .onSurfaceVariant,
                                                            ),
                                                      ),
                                                    ],
                                                  ),
                                                  trailing:
                                                      EmployeePresenceBadge(
                                                        firestore:
                                                            widget.firestore,
                                                        tracked: e,
                                                        compact: true,
                                                      ),
                                                  onTap: () => context.go(
                                                    '/employees/detail/${e.id}',
                                                  ),
                                                );
                                              },
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
                } catch (e, st) {
                  if (kDebugMode) {
                    debugPrint('[Dashboard] live host builder failed: $e');
                    debugPrintStack(
                      stackTrace: st,
                      label: 'dashboard_live_host_builder',
                    );
                  }
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Dashboard layout error. Pull to refresh or use Refresh data.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
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
    return m.entries
        .map((e) => '${e.key} ${e.value.toStringAsFixed(2)}')
        .join(' · ');
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
    final scheme = Theme.of(context).colorScheme;
    final iconBg = Color.alphaBlend(
      scheme.primary.withValues(alpha: 0.12),
      scheme.surface,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppLayout.cardPadding),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Icon(icon, size: 26, color: scheme.primary),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.85),
                        height: 1.25,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  loading
                      ? const SizedBox(
                          height: 24,
                          width: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          value,
                          style: denseValue
                              ? Theme.of(
                                  context,
                                ).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.2,
                                )
                              : Theme.of(
                                  context,
                                ).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.3,
                                ),
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
