import 'package:flutter/material.dart';

import '../../../core/utils/employee_name_utils.dart';
import '../../../models/employer_group.dart';
import '../../../models/tracked_employee.dart';
import '../../../services/firestore_service.dart';

/// Bulk assign / unassign [groupId] on eligible tracked employees (other groupIds untouched).
Future<void> showManageGroupMembersDialog(
  BuildContext context, {
  required FirestoreService firestore,
  required String employerUid,
  required EmployerGroup group,
  required List<TrackedEmployee> eligibleEmployees,
}) async {
  final selected = <String, bool>{
    for (final t in eligibleEmployees) t.id: t.groupIds.contains(group.id),
  };
  var loading = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: Text('Manage members — ${group.name}'),
            content: SizedBox(
              width: 440,
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Only tracked employees with at least one shared workspace appear here. '
                    'Changes affect only this group.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (eligibleEmployees.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          'No eligible employees.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: eligibleEmployees.length,
                        itemBuilder: (context, i) {
                          final t = eligibleEmployees[i];
                          final checked = selected[t.id] ?? false;
                          return CheckboxListTile(
                            value: checked,
                            onChanged: loading
                                ? null
                                : (v) {
                                    setLocal(() => selected[t.id] = v ?? false);
                                  },
                            title: Text(employeeFullName(t)),
                            subtitle: employeeShowEmailAsSubtitle(t)
                                ? Text(
                                    t.employeeEmail,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : null,
                          );
                        },
                      ),
                    ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: loading || eligibleEmployees.isEmpty
                    ? null
                    : () async {
                        setLocal(() {
                          loading = true;
                          error = null;
                        });
                        try {
                          await firestore
                              .applyTrackedEmployeesMembershipInGroup(
                                employerUid: employerUid,
                                groupId: group.id,
                                trackedIdInGroup: Map<String, bool>.from(
                                  selected,
                                ),
                              );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx);
                        } catch (e) {
                          setLocal(() {
                            loading = false;
                            error = 'Could not save: $e';
                          });
                        }
                      },
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
}
