import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../services/firestore_service.dart';

Future<void> showAddEmployeeDialog(BuildContext context, FirestoreService firestore) async {
  final emailCtrl = TextEditingController();
  final companyCtrl = TextEditingController();
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
            final company = companyCtrl.text.trim();
            if (workEmail.isEmpty || company.isEmpty) {
              setLocal(() => error = 'Fill in both fields.');
              return;
            }
            setLocal(() {
              loading = true;
              error = null;
            });
            try {
              await firestore.linkEmployee(
                employerUid: employer.uid,
                employerEmail: employer.email ?? '',
                employeeWorkEmailInput: workEmail,
                companyNameInput: company,
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
            title: const Text('Add employee'),
            content: SizedBox(
              width: 400,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: emailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Employee work email',
                      hintText: 'name@company.com',
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: companyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Company name',
                      hintText: 'Matches workspace company slug (normalized)',
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
