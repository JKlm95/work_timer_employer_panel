import 'package:flutter/material.dart';

import '../../../services/firestore_service.dart';

/// Returns `true` if the group was deleted.
Future<bool> showDeleteGroupDialog(
  BuildContext context, {
  required FirestoreService firestore,
  required String employerUid,
  required String groupId,
}) async {
  var removeFromEmployees = true;
  var loading = false;
  String? error;

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          return AlertDialog(
            title: const Text('Delete group'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Deleting this group will not delete employees or their time entries.',
                  ),
                  const SizedBox(height: 16),
                  CheckboxListTile(
                    value: removeFromEmployees,
                    onChanged: loading
                        ? null
                        : (v) =>
                              setLocal(() => removeFromEmployees = v ?? true),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: const Text('Remove this group from employees'),
                    subtitle: const Text(
                      'Recommended: clears stale groupIds on tracked employees.',
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: loading
                    ? null
                    : () async {
                        setLocal(() {
                          loading = true;
                          error = null;
                        });
                        try {
                          await firestore.deleteGroup(
                            employerUid,
                            groupId,
                            removeReferencesFromEmployees: removeFromEmployees,
                          );
                          if (!ctx.mounted) return;
                          Navigator.pop(ctx, true);
                        } catch (e) {
                          setLocal(() {
                            loading = false;
                            error = 'Could not delete group: $e';
                          });
                        }
                      },
                child: loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Delete group'),
              ),
            ],
          );
        },
      );
    },
  );
  return result == true;
}
