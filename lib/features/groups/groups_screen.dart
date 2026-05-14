import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_layout.dart';
import '../../core/utils/employee_name_utils.dart';
import '../../core/utils/employer_group_ids_utils.dart';
import '../../core/widgets/employee_presence_badge.dart';
import '../../models/employer_group.dart';
import '../../models/tracked_employee.dart';
import '../../models/tracked_workspace_access.dart';
import '../../services/firestore_service.dart';
import 'widgets/create_group_dialog.dart';
import 'widgets/delete_group_dialog.dart';
import 'widgets/manage_group_members_dialog.dart';
import 'widgets/rename_group_dialog.dart';

class GroupsScreen extends StatefulWidget {
  const GroupsScreen({super.key, required this.firestore});

  final FirestoreService firestore;

  @override
  State<GroupsScreen> createState() => _GroupsScreenState();
}

class _GroupsScreenState extends State<GroupsScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<EmployerGroup> _filterGroupsBySearch(List<EmployerGroup> groups) {
    final q = _searchCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return groups;
    return groups.where((g) => g.name.toLowerCase().contains(q)).toList();
  }

  List<TrackedEmployee> _membersForGroup(
    EmployerGroup g,
    List<TrackedEmployee> eligible,
  ) {
    return eligible.where((t) => t.groupIds.contains(g.id)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(AppLayout.pagePadding),
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
                    onPressed: () async {
                      final list = await widget.firestore
                          .groupsStream(uid)
                          .first;
                      if (!context.mounted) return;
                      showCreateGroupDialog(
                        context,
                        widget.firestore,
                        existingGroups: list,
                      );
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('Create group'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Organize tracked employees into groups. Groups do not change '
                'permissions — access still comes only from shared workspaces '
                '(trackedWorkspaces).',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  hintText: 'Search groups…',
                  isDense: true,
                  prefixIcon: Icon(Icons.search, size: 22),
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: StreamBuilder<List<TrackedWorkspaceAccess>>(
                  stream: widget.firestore.trackedWorkspaceAccessStream(uid),
                  builder: (context, accessSnap) {
                    if (accessSnap.hasError) {
                      return _InlineErrorCard(
                        title: 'Could not load workspace access',
                        message: '${accessSnap.error}',
                      );
                    }
                    final access = accessSnap.data ?? [];
                    final uidsWithWorkspace = access
                        .map((a) => a.employeeUid.trim())
                        .where((u) => u.isNotEmpty)
                        .toSet();

                    return StreamBuilder<List<TrackedEmployee>>(
                      stream: widget.firestore.trackedEmployeesStream(uid),
                      builder: (context, trackedSnap) {
                        if (trackedSnap.hasError) {
                          return _InlineErrorCard(
                            title: 'Could not load employees',
                            message: '${trackedSnap.error}',
                          );
                        }
                        if (trackedSnap.connectionState ==
                                ConnectionState.waiting &&
                            !trackedSnap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        return StreamBuilder<List<EmployerGroup>>(
                          stream: widget.firestore.groupsStream(uid),
                          builder: (context, groupsSnap) {
                            if (groupsSnap.hasError) {
                              return _InlineErrorCard(
                                title: 'Could not load groups',
                                message: '${groupsSnap.error}',
                              );
                            }
                            if (groupsSnap.connectionState ==
                                    ConnectionState.waiting &&
                                !groupsSnap.hasData) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }

                            final allGroups = groupsSnap.data ?? [];
                            final tracked = trackedSnap.data ?? [];
                            final eligible = tracked
                                .where(
                                  (t) =>
                                      uidsWithWorkspace.contains(t.employeeUid),
                                )
                                .toList();
                            final existingIds = allGroups
                                .map((g) => g.id)
                                .toSet();

                            void openCreate() {
                              showCreateGroupDialog(
                                context,
                                widget.firestore,
                                existingGroups: allGroups,
                              );
                            }

                            if (allGroups.isEmpty) {
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(32),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'No groups yet',
                                        textAlign: TextAlign.center,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Create a group to organize your employees.',
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
                                        onPressed: openCreate,
                                        icon: const Icon(Icons.add),
                                        label: const Text('Create group'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            final groups = _filterGroupsBySearch(allGroups);
                            if (groups.isEmpty) {
                              return Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Text(
                                        'No groups match your search.',
                                      ),
                                      const SizedBox(height: 12),
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          _searchCtrl.clear();
                                          setState(() {});
                                        },
                                        icon: const Icon(Icons.clear),
                                        label: const Text('Clear search'),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }

                            final ungrouped = eligible
                                .where(
                                  (t) => !employeeHasAnyValidGroupAssignment(
                                    t.groupIds,
                                    existingIds,
                                  ),
                                )
                                .toList();

                            return ListView(
                              children: [
                                for (final g in groups) ...[
                                  _GroupExpansionCard(
                                    group: g,
                                    members: _membersForGroup(g, eligible),
                                    firestore: widget.firestore,
                                    onRename: () => showRenameGroupDialog(
                                      context,
                                      widget.firestore,
                                      group: g,
                                      existingGroups: allGroups,
                                    ),
                                    onDelete: () async {
                                      final ok = await showDeleteGroupDialog(
                                        context,
                                        firestore: widget.firestore,
                                        employerUid: uid,
                                        groupId: g.id,
                                      );
                                      if (ok && context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          const SnackBar(
                                            content: Text('Group deleted.'),
                                          ),
                                        );
                                      }
                                    },
                                    onManageMembers: () =>
                                        showManageGroupMembersDialog(
                                          context,
                                          firestore: widget.firestore,
                                          employerUid: uid,
                                          group: g,
                                          eligibleEmployees: eligible,
                                        ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                                _UngroupedExpansionCard(
                                  employees: ungrouped,
                                  firestore: widget.firestore,
                                ),
                              ],
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
}

class _InlineErrorCard extends StatelessWidget {
  const _InlineErrorCard({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
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
              title,
              style: Theme.of(context).textTheme.titleSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            SelectableText(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupExpansionCard extends StatelessWidget {
  const _GroupExpansionCard({
    required this.group,
    required this.members,
    required this.firestore,
    required this.onRename,
    required this.onDelete,
    required this.onManageMembers,
  });

  final EmployerGroup group;
  final List<TrackedEmployee> members;
  final FirestoreService firestore;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onManageMembers;

  @override
  Widget build(BuildContext context) {
    final n = members.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: PageStorageKey<Object>('group-${group.id}'),
          title: Text(
            group.name,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '$n ${n == 1 ? 'employee' : 'employees'}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: onManageMembers,
                    icon: const Icon(Icons.group_outlined),
                    label: const Text('Manage members'),
                  ),
                  TextButton.icon(
                    onPressed: onRename,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Rename'),
                  ),
                  TextButton.icon(
                    onPressed: onDelete,
                    icon: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    label: Text(
                      'Delete',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (members.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'No employees in this group',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...members.map(
                (t) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(employeeFullName(t)),
                  subtitle: employeeShowEmailAsSubtitle(t)
                      ? Text(
                          t.employeeEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  leading: EmployeePresenceBadge(
                    firestore: firestore,
                    tracked: t,
                    compact: true,
                  ),
                  trailing: IconButton(
                    tooltip: 'Employee details',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => context.push('/employees/detail/${t.id}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UngroupedExpansionCard extends StatelessWidget {
  const _UngroupedExpansionCard({
    required this.employees,
    required this.firestore,
  });

  final List<TrackedEmployee> employees;
  final FirestoreService firestore;

  @override
  Widget build(BuildContext context) {
    final n = employees.length;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          key: const PageStorageKey<Object>('ungrouped-section'),
          initiallyExpanded: true,
          title: const Text(
            'Ungrouped',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: Text(
            '$n ${n == 1 ? 'employee' : 'employees'} · no valid group assignment',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
          children: [
            if (employees.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'All employees are assigned to groups',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ...employees.map(
                (t) => ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  title: Text(employeeFullName(t)),
                  subtitle: employeeShowEmailAsSubtitle(t)
                      ? Text(
                          t.employeeEmail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : null,
                  leading: EmployeePresenceBadge(
                    firestore: firestore,
                    tracked: t,
                    compact: true,
                  ),
                  trailing: IconButton(
                    tooltip: 'Employee details',
                    icon: const Icon(Icons.chevron_right),
                    onPressed: () => context.push('/employees/detail/${t.id}'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
