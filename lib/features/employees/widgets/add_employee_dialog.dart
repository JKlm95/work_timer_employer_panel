import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/firestore_service.dart';

Future<void> showAddEmployeeDialog(
  BuildContext context,
  FirestoreService firestore,
) async {
  final emailCtrl = TextEditingController();
  bool loading = false;
  String? error;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> submit() async {
            final employer = FirebaseAuth.instance.currentUser;
            if (employer == null) return;
            final workEmail = emailCtrl.text.trim();
            if (workEmail.isEmpty) {
              setLocal(() => error = 'Enter the employee work email.');
              return;
            }
            setLocal(() {
              loading = true;
              error = null;
            });
            try {
              await firestore.linkEmployeeByWorkEmail(
                employerUid: employer.uid,
                employerEmail: employer.email ?? '',
                employeeWorkEmailInput: workEmail,
              );
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
            } on EmployerLinkException catch (e) {
              if (context.mounted) {
                setLocal(() {
                  loading = false;
                  error = e.message;
                });
              }
            } catch (_) {
              if (context.mounted) {
                setLocal(() {
                  loading = false;
                  error = 'Could not add employee. Try again.';
                });
              }
            }
          }

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            actionsAlignment: MainAxisAlignment.end,
            title: const Text('Add employee'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Enter the work email the employee set on their shared workspace in the mobile app. '
                    'It must match your company email domain.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Employee work email',
                      hintText: 'name@company.com',
                      helperText:
                          'Enter the employee’s work email used in the shared workspace.',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 14),
                    Material(
                      color: Theme.of(
                        context,
                      ).colorScheme.errorContainer.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline_rounded,
                              size: 20,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                error!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onErrorContainer,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: loading ? null : () => Navigator.pop(dialogContext),
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
                    : const Text('Add'),
              ),
            ],
          );
        },
      );
    },
  );
}
