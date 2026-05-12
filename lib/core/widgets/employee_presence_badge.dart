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
        final state = resolveWorkPresence(live: snap.data, tracked: tracked);
        return WorkStatusBadge(state: state, compact: compact);
      },
    );
  }
}
