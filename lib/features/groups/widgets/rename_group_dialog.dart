import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../core/utils/employer_group_ids_utils.dart';
import '../../../models/employer_group.dart';
import '../../../services/firestore_service.dart';

Future<void> showRenameGroupDialog(
  BuildContext context,
  FirestoreService firestore, {
  required EmployerGroup group,
  List<EmployerGroup> existingGroups = const [],
}) async {
  final nameCtrl = TextEditingController(text: group.name);
  var loading = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> submit() async {
            final uid = FirebaseAuth.instance.currentUser?.uid;
            if (uid == null) return;
            final name = nameCtrl.text.trim();
            if (name.isEmpty) {
              setLocal(() => error = 'Enter a group name.');
              return;
            }
            if (name.length > kMaxEmployerGroupNameLength) {
              setLocal(
                () => error =
                    'Name is too long (max $kMaxEmployerGroupNameLength characters).',
              );
              return;
            }
            if (employerGroupNameCollides(
              name,
              existingGroups,
              ignoreGroupId: group.id,
            )) {
              setLocal(() => error = 'A group with this name already exists.');
              return;
            }
            setLocal(() {
              loading = true;
              error = null;
            });
            try {
              await firestore.updateGroupName(uid, group.id, name: name);
              if (!ctx.mounted) return;
              ScaffoldMessenger.of(
                ctx,
              ).showSnackBar(const SnackBar(content: Text('Group renamed.')));
              Navigator.of(ctx).pop();
            } catch (e) {
              setLocal(() {
                error = 'Could not rename group: $e';
                loading = false;
              });
            }
          }

          return AlertDialog(
            title: const Text('Rename group'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                    autofocus: true,
                    maxLength: kMaxEmployerGroupNameLength,
                    onChanged: (_) => setLocal(() {}),
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
                onPressed: loading ? null : () => Navigator.pop(ctx),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: loading ? null : submit,
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
