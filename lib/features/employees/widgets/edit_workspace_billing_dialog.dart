import 'package:flutter/material.dart';

import '../../../models/workspace.dart';
import '../../../services/firestore_service.dart';

/// Edit [Workspace.hourlyRate] and [Workspace.currency] (Firestore source of truth for MVP).
Future<void> showEditWorkspaceBillingDialog(
  BuildContext context, {
  required String employerUid,
  required FirestoreService firestore,
  required String employeeUid,
  required Workspace workspace,
}) async {
  final rateCtrl = TextEditingController(
    text: workspace.hourlyRate != null
        ? workspace.hourlyRate!.toStringAsFixed(2)
        : '',
  );
  var currency = (workspace.currency ?? 'PLN').toUpperCase();
  if (!const {'PLN', 'EUR', 'USD', 'GBP'}.contains(currency)) {
    currency = 'PLN';
  }
  String? error;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (context, setLocal) {
          Future<void> save() async {
            final parsed = double.tryParse(rateCtrl.text.replaceAll(',', '.'));
            if (parsed == null) {
              setLocal(() => error = 'Enter a valid number.');
              return;
            }
            setLocal(() => error = null);
            try {
              await firestore.updateWorkspaceBilling(
                employerUid: employerUid,
                employeeUid: employeeUid,
                workspaceId: workspace.id,
                hourlyRate: parsed,
                currency: currency,
              );
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            } on WorkspaceBillingException catch (e) {
              setLocal(() => error = e.message);
            } catch (_) {
              setLocal(() => error = 'Could not save. Try again.');
            }
          }

          return AlertDialog(
            title: const Text('Edit hourly rate'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    workspace.name,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: rateCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Hourly rate',
                      hintText: '0.00',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    // ignore: deprecated_member_use
                    value: currency,
                    decoration: const InputDecoration(labelText: 'Currency'),
                    items: const [
                      DropdownMenuItem(value: 'PLN', child: Text('PLN')),
                      DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      DropdownMenuItem(value: 'USD', child: Text('USD')),
                      DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                    ],
                    onChanged: (v) => setLocal(() => currency = v ?? 'PLN'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    // TODO(mobile): see FirestoreService.updateWorkspaceBilling
                    'Saved to Firestore. Mobile app should read server values after sync.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 8),
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
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: save, child: const Text('Save')),
            ],
          );
        },
      );
    },
  );
}
