import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../models/employer_group.dart';
import '../../models/tracked_employee.dart';
import '../../services/firestore_service.dart';
import 'widgets/create_group_dialog.dart';

class GroupsScreen extends StatelessWidget {
  const GroupsScreen({super.key, required this.firestore});

  final FirestoreService firestore;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text(
                    'Groups',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => showCreateGroupDialog(context, firestore),
                    icon: const Icon(Icons.add),
                    label: const Text('Create group'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Groups only organize employees for you — they do not change employee data.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<TrackedEmployee>>(
                  stream: firestore.trackedEmployeesStream(uid),
                  builder: (context, trackedSnap) {
                    if (trackedSnap.hasError) {
                      return Card(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.cloud_off_outlined,
                                size: 40,
                                color: Theme.of(context).colorScheme.error,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Could not load employees',
                                style: Theme.of(context).textTheme.titleSmall,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              SelectableText(
                                '${trackedSnap.error}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                    final tracked = trackedSnap.data ?? [];
                    return StreamBuilder<List<EmployerGroup>>(
                      stream: firestore.groupsStream(uid),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cloud_off_outlined,
                                    size: 40,
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'Could not load groups',
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  SelectableText(
                                    '${snap.error}',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }
                        if (snap.connectionState == ConnectionState.waiting &&
                            !snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final groups = snap.data ?? [];
                        if (groups.isEmpty) {
                          return Card(
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(32),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'No groups created yet.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Create groups to organize employees by project, team or department.',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                    const SizedBox(height: 24),
                                    FilledButton.icon(
                                      onPressed: () => showCreateGroupDialog(
                                        context,
                                        firestore,
                                      ),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Create group'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: groups.length,
                          separatorBuilder: (context, _) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, i) {
                            final g = groups[i];
                            final count = tracked
                                .where((t) => t.groupIds.contains(g.id))
                                .length;
                            return Card(
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: _hex(g.colorHex),
                                  child: const SizedBox.shrink(),
                                ),
                                title: Text(g.name),
                                subtitle: Text(
                                  '$count ${count == 1 ? 'employee' : 'employees'} · ${g.colorHex}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'Rename',
                                      icon: const Icon(Icons.edit_outlined),
                                      onPressed: () => _edit(context, uid, g),
                                    ),
                                    IconButton(
                                      tooltip: 'Delete',
                                      icon: Icon(
                                        Icons.delete_outline,
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                      ),
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (c) => AlertDialog(
                                            title: const Text('Delete group'),
                                            content: const Text(
                                              'Employees will be unassigned from this group.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, false),
                                                child: const Text('Cancel'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(c, true),
                                                child: const Text('Delete'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true && context.mounted) {
                                          await firestore.deleteGroup(
                                            uid,
                                            g.id,
                                          );
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
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
  }

  Color _hex(String hex) {
    try {
      var h = hex.replaceFirst('#', '');
      if (h.length == 6) h = 'FF$h';
      return Color(int.parse(h, radix: 16));
    } catch (_) {
      return Colors.blueGrey;
    }
  }

  Future<void> _edit(
    BuildContext context,
    String employerUid,
    EmployerGroup g,
  ) async {
    final nameCtrl = TextEditingController(text: g.name);
    final colorCtrl = TextEditingController(text: g.colorHex);
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: colorCtrl,
              decoration: const InputDecoration(labelText: 'Color (hex)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              var hex = colorCtrl.text.trim();
              if (!hex.startsWith('#')) hex = '#$hex';
              await firestore.updateGroup(
                employerUid,
                g.id,
                name: nameCtrl.text.trim(),
                colorHex: hex,
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
