import 'package:cloud_firestore/cloud_firestore.dart';

/// Update payload for employer soft-delete (`isDeleted: true`).
Map<String, dynamic> employerEntrySoftDeletePatch(String editedBy) {
  return {
    'isDeleted': true,
    'updatedAt': FieldValue.serverTimestamp(),
    'editedAt': FieldValue.serverTimestamp(),
    'editedBy': editedBy,
  };
}

/// Update payload for restoring a soft-deleted entry.
Map<String, dynamic> employerEntryRestorePatch(String editedBy) {
  return {
    'isDeleted': false,
    'updatedAt': FieldValue.serverTimestamp(),
    'editedAt': FieldValue.serverTimestamp(),
    'editedBy': editedBy,
  };
}
