import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app.dart';
import 'core/debug/employer_entries_debug_config.dart';
import 'core/theme/theme_controller.dart';
import 'firebase_options.dart';
import 'router/app_router.dart';
import 'services/firestore_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final themeController = ThemeController();
  await themeController.load();

  final firestore = FirestoreService();
  final router = createAppRouter(firestore: firestore);

  EmployerEntriesDebugConfig.verboseTrace = true;
  EmployerEntriesDebugConfig.focusEmployeeUid =
      'K2GpWnbmArTL4uMiJzHbO5tHtMq2';
  EmployerEntriesDebugConfig.focusEntryId =
      'b9296bc7-6d33-45ed-8c01-2b6e73b1c526';

  runApp(
    ChangeNotifierProvider.value(
      value: themeController,
      child: WorkTimerEmployerApp(router: router),
    ),
  );
}
