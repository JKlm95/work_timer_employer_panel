import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/theme/theme_controller.dart';
import '../../services/firestore_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.firestore});

  final FirestoreService firestore;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _rebuilding = false;
  String? _rebuildMessage;

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final themeController = context.watch<ThemeController>();

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Settings',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Appearance',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Light, dark, or match your system.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SegmentedButton<ThemeMode>(
                        segments: const [
                          ButtonSegment(
                            value: ThemeMode.system,
                            label: Text('System'),
                            icon: Icon(Icons.brightness_auto_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.light,
                            label: Text('Light'),
                            icon: Icon(Icons.light_mode_outlined),
                          ),
                          ButtonSegment(
                            value: ThemeMode.dark,
                            label: Text('Dark'),
                            icon: Icon(Icons.dark_mode_outlined),
                          ),
                        ],
                        selected: {themeController.mode},
                        onSelectionChanged: (set) {
                          if (set.isEmpty) return;
                          context.read<ThemeController>().setMode(set.first);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Workspace access',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Rebuild `trackedWorkspaces` from each linked employee’s shared '
                        'workspaces (isSharedWithEmployer, employee work email + domain). '
                        'Run after deploying the new access model or when data looks wrong.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          height: 1.35,
                        ),
                      ),
                      if (_rebuildMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _rebuildMessage!,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                      const SizedBox(height: 16),
                      FilledButton.tonalIcon(
                        onPressed: _rebuilding || user?.uid == null
                            ? null
                            : () async {
                                final email = user?.email ?? '';
                                if (email.isEmpty) {
                                  setState(() {
                                    _rebuildMessage =
                                        'Signed-in user has no email; cannot rebuild.';
                                  });
                                  return;
                                }
                                setState(() {
                                  _rebuilding = true;
                                  _rebuildMessage = null;
                                });
                                try {
                                  final n = await widget.firestore
                                      .rebuildTrackedWorkspaceAccess(
                                        employerUid: user!.uid,
                                        employerEmail: email,
                                        preferServer: true,
                                      );
                                  if (mounted) {
                                    setState(() {
                                      _rebuildMessage =
                                          'Done. Matched $n workspace link(s) '
                                          '(rows considered before de-duplication by employee).';
                                    });
                                  }
                                } catch (e) {
                                  if (mounted) {
                                    setState(() {
                                      _rebuildMessage = 'Rebuild failed: $e';
                                    });
                                  }
                                } finally {
                                  if (mounted) {
                                    setState(() => _rebuilding = false);
                                  }
                                }
                              },
                        icon: _rebuilding
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cleaning_services_outlined),
                        label: Text(
                          _rebuilding
                              ? 'Rebuilding…'
                              : 'Rebuild workspace access',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Signed in as',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 4),
                      SelectableText(user?.email ?? '—'),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) context.go('/login');
                },
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
