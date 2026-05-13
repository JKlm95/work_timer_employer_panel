import 'package:firebase_auth/firebase_auth.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/employees/employee_detail_screen.dart';
import '../features/employees/employees_screen.dart';
import '../features/groups/groups_screen.dart';
import '../features/reports/payroll_screen.dart';
import '../features/reports/project_report_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/shell/main_shell.dart';
import '../services/firestore_service.dart';
import 'go_router_refresh.dart';

GoRouter createAppRouter({required FirestoreService firestore}) {
  final refresh = GoRouterRefreshStream(
    FirebaseAuth.instance.authStateChanges(),
  );

  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = FirebaseAuth.instance.currentUser != null;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn && !loggingIn) return '/login';
      if (loggedIn && loggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      ShellRoute(
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            builder: (context, state) => DashboardScreen(firestore: firestore),
          ),
          GoRoute(
            path: '/employees',
            builder: (context, state) => EmployeesScreen(firestore: firestore),
            routes: [
              GoRoute(
                path: 'detail/:trackedId',
                builder: (context, state) {
                  final id = state.pathParameters['trackedId']!;
                  return EmployeeDetailScreen(
                    firestore: firestore,
                    trackedId: id,
                  );
                },
                routes: [
                  GoRoute(
                    path: 'workspace/:workspaceId/report',
                    builder: (context, state) {
                      final trackedId = state.pathParameters['trackedId']!;
                      final workspaceId = state.pathParameters['workspaceId']!;
                      return ProjectReportScreen(
                        firestore: firestore,
                        trackedId: trackedId,
                        workspaceId: workspaceId,
                      );
                    },
                  ),
                ],
              ),
            ],
          ),
          GoRoute(
            path: '/groups',
            builder: (context, state) => GroupsScreen(firestore: firestore),
          ),
          GoRoute(
            path: '/payroll',
            builder: (context, state) => PayrollScreen(firestore: firestore),
          ),
          GoRoute(
            path: '/settings',
            builder: (context, state) => const SettingsScreen(),
          ),
        ],
      ),
    ],
  );
}
