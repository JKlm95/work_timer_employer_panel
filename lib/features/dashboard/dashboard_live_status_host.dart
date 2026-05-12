import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/employee_live_status.dart';
import '../../models/tracked_employee.dart';
import '../../services/firestore_service.dart';

/// Subscribes to `live/status` for each tracked employee and ticks every [tickInterval]
/// so running-session UI can update elapsed time without polling Firestore.
class DashboardLiveStatusHost extends StatefulWidget {
  const DashboardLiveStatusHost({
    super.key,
    required this.tracked,
    required this.firestore,
    required this.builder,
    this.tickInterval = const Duration(seconds: 1),
  });

  final List<TrackedEmployee> tracked;
  final FirestoreService firestore;
  final Widget Function(BuildContext context, Map<String, EmployeeLiveStatus?> liveByUid) builder;
  final Duration tickInterval;

  @override
  State<DashboardLiveStatusHost> createState() => _DashboardLiveStatusHostState();
}

class _DashboardLiveStatusHostState extends State<DashboardLiveStatusHost> {
  final Map<String, EmployeeLiveStatus?> _live = {};
  final List<StreamSubscription<EmployeeLiveStatus?>> _subs = [];
  Timer? _tick;
  String _trackedSig = '';

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(widget.tickInterval, (_) {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    _cancelSubs();
    super.dispose();
  }

  void _cancelSubs() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
  }

  void _resubscribeIfNeeded() {
    final sig = widget.tracked.map((e) => '${e.id}:${e.employeeUid}').join('|');
    if (sig == _trackedSig) return;
    _trackedSig = sig;
    _cancelSubs();
    _live.clear();
    for (final t in widget.tracked) {
      final uid = t.employeeUid;
      if (uid.isEmpty) continue;
      _subs.add(
        widget.firestore.employeeLiveStatusStream(uid).listen((v) {
          if (!mounted) return;
          setState(() => _live[uid] = v);
        }),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    _resubscribeIfNeeded();
    return widget.builder(context, Map<String, EmployeeLiveStatus?>.from(_live));
  }
}
