import 'package:flutter/material.dart';

import '../../../core/utils/employee_name_utils.dart';
import '../../../models/employer_group.dart';
import '../../../models/tracked_employee.dart';
import '../../../services/firestore_service.dart';

Future<void> showAssignGroupsSheet(
  BuildContext context, {
  required FirestoreService firestore,
  required String employerUid,
  required TrackedEmployee tracked,
  required List<EmployerGroup> allGroups,
}) async {
  final selected = List<String>.from(tracked.groupIds);

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(ctx).viewInsets.bottom,
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'Assign groups',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      employeeFullName(tracked),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (employeeShowEmailAsSubtitle(tracked))
                      Text(
                        tracked.employeeEmail,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (allGroups.isEmpty)
                      const Text('Create a group first on the Groups page.')
                    else
                      ...allGroups.map(
                        (g) => CheckboxListTile(
                          value: selected.contains(g.id),
                          onChanged: (v) {
                            setLocal(() {
                              if (v == true) {
                                selected.add(g.id);
                              } else {
                                selected.remove(g.id);
                              }
                            });
                          },
                          title: Text(g.name),
                          secondary: CircleAvatar(
                            backgroundColor:
                                _parseHex(g.colorHex) ?? Colors.grey,
                            radius: 12,
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: allGroups.isEmpty
                          ? null
                          : () async {
                              await firestore.setTrackedEmployeeGroups(
                                employerUid,
                                tracked.id,
                                selected,
                              );
                              if (context.mounted) Navigator.pop(context);
                            },
                      child: const Text('Save'),
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

Color? _parseHex(String hex) {
  var h = hex.replaceFirst('#', '');
  if (h.length == 6) {
    h = 'FF$h';
  }
  if (h.length != 8) return null;
  return Color(int.parse(h, radix: 16));
}
