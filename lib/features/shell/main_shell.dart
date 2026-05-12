import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.child});

  final Widget child;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  int _indexForLocation(String location) {
    if (location.startsWith('/dashboard')) return 0;
    if (location.startsWith('/employees')) return 1;
    if (location.startsWith('/groups')) return 2;
    if (location.startsWith('/payroll')) return 3;
    if (location.startsWith('/settings')) return 4;
    return 0;
  }

  void _go(int i, BuildContext context) {
    switch (i) {
      case 0:
        context.go('/dashboard');
        break;
      case 1:
        context.go('/employees');
        break;
      case 2:
        context.go('/groups');
        break;
      case 3:
        context.go('/payroll');
        break;
      case 4:
        context.go('/settings');
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).uri.path;
    final selected = _indexForLocation(location);
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    final wide = MediaQuery.sizeOf(context).width >= 900;

    final destinations = [
      const NavigationRailDestination(icon: Icon(Icons.dashboard_outlined), label: Text('Dashboard')),
      const NavigationRailDestination(icon: Icon(Icons.people_outline), label: Text('Employees')),
      const NavigationRailDestination(icon: Icon(Icons.folder_special_outlined), label: Text('Groups')),
      const NavigationRailDestination(icon: Icon(Icons.payments_outlined), label: Text('Payroll report')),
      const NavigationRailDestination(icon: Icon(Icons.settings_outlined), label: Text('Settings')),
    ];

    if (wide) {
      return Scaffold(
        body: Row(
          children: [
            NavigationRail(
              extended: MediaQuery.sizeOf(context).width >= 1100,
              selectedIndex: selected,
              onDestinationSelected: (i) => _go(i, context),
              leading: Padding(
                padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
                child: Icon(Icons.schedule_rounded, color: Theme.of(context).colorScheme.primary),
              ),
              destinations: destinations,
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _TopBar(email: email),
                  Expanded(child: widget.child),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('Work Timer — Employer'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Center(
              child: Text(
                email,
                style: Theme.of(context).textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.primaryContainer),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'Menu',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.dashboard_outlined),
              title: const Text('Dashboard'),
              selected: selected == 0,
              onTap: () {
                Navigator.pop(context);
                context.go('/dashboard');
              },
            ),
            ListTile(
              leading: const Icon(Icons.people_outline),
              title: const Text('Employees'),
              selected: selected == 1,
              onTap: () {
                Navigator.pop(context);
                context.go('/employees');
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_special_outlined),
              title: const Text('Groups'),
              selected: selected == 2,
              onTap: () {
                Navigator.pop(context);
                context.go('/groups');
              },
            ),
            ListTile(
              leading: const Icon(Icons.payments_outlined),
              title: const Text('Payroll report'),
              selected: selected == 3,
              onTap: () {
                Navigator.pop(context);
                context.go('/payroll');
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('Settings'),
              selected: selected == 4,
              onTap: () {
                Navigator.pop(context);
                context.go('/settings');
              },
            ),
          ],
        ),
      ),
      body: widget.child,
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Text(
              'Employer panel',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(Icons.mail_outline, size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                email.isEmpty ? '—' : email,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
