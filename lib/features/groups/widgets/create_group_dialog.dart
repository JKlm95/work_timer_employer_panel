import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/firestore_service.dart';

Future<void> showCreateGroupDialog(
  BuildContext context,
  FirestoreService firestore,
) async {
  final nameCtrl = TextEditingController();
  final colorCtrl = TextEditingController(text: '#6366F1');
  bool loading = false;
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
            var hex = colorCtrl.text.trim();
            if (!hex.startsWith('#')) hex = '#$hex';
            setLocal(() {
              loading = true;
              error = null;
            });
            try {
              await firestore.createGroup(uid, name: name, colorHex: hex);
              if (context.mounted) Navigator.of(context).pop();
            } catch (_) {
              setLocal(() => error = 'Could not create group.');
            } finally {
              setLocal(() => loading = false);
            }
          }

          return AlertDialog(
            title: const Text('Create group'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(labelText: 'Name'),
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: colorCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Color (hex)',
                      hintText: '#6366F1',
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
                onPressed: loading ? null : () => Navigator.pop(context),
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
                    : const Text('Create'),
              ),
            ],
          );
        },
      );
    },
  );
}
