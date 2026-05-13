import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/employee_live_status.dart';
import '../../models/tracked_employee.dart';
import '../../services/firestore_service.dart';
import '../utils/employee_presence_utils.dart';
import 'work_status_badge.dart';

/// Listens to `users/{uid}/live/status` and shows [WorkPresenceState].
class EmployeePresenceBadge extends StatelessWidget {
  const EmployeePresenceBadge({
    super.key,
    required this.firestore,
    required this.tracked,
    this.compact = false,
  });

  final FirestoreService firestore;
  final TrackedEmployee tracked;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EmployeeLiveStatus?>(
      stream: firestore.employeeLiveStatusStream(tracked.employeeUid),
      builder: (context, snap) {
        if (snap.hasError) {
          if (kDebugMode) {
            debugPrint(
              '[LiveStatus] StreamBuilder error uid=${tracked.employeeUid} tracked=${tracked.id} ${snap.error}',
            );
            final st = snap.stackTrace;
            if (st != null) {
              debugPrintStack(
                stackTrace: st,
                label: 'employee_presence_stream',
              );
            }
          }
          return WorkStatusBadge(
            state: WorkPresenceState.unknown,
            compact: compact,
          );
        }

        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return WorkStatusBadge(
            state: WorkPresenceState.unknown,
            compact: compact,
          );
        }

        final live = snap.data;
        try {
          final state = resolveWorkPresence(live: live);
          return WorkStatusBadge(state: state, compact: compact);
        } catch (e, st) {
          if (kDebugMode) {
            debugPrint(
              '[LiveStatus] resolveWorkPresence failed uid=${tracked.employeeUid}: $e',
            );
            debugPrintStack(stackTrace: st, label: 'employee_presence_resolve');
          }
          return WorkStatusBadge(
            state: WorkPresenceState.unknown,
            compact: compact,
          );
        }
      },
    );
  }
}
