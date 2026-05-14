import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// `employeeWorkEmailIndex/{workEmailLower}` — mobile-maintained map from work email to uid + workspace ids.
class EmployeeWorkEmailIndex extends Equatable {
  const EmployeeWorkEmailIndex({
    required this.uid,
    required this.workEmailLower,
    required this.domain,
    required this.workspaceIds,
    this.updatedAt,
  });

  final String uid;
  final String workEmailLower;
  final String domain;
  final List<String> workspaceIds;
  final DateTime? updatedAt;

  factory EmployeeWorkEmailIndex.fromDoc(
    String docId,
    Map<String, dynamic> data,
  ) {
    final rawIds = data['workspaceIds'];
    final ids = <String>[];
    final seen = <String>{};
    if (rawIds is List) {
      for (final e in rawIds) {
        final s = e?.toString().trim() ?? '';
        if (s.isNotEmpty && seen.add(s)) ids.add(s);
      }
    }
    return EmployeeWorkEmailIndex(
      uid: (data['uid'] as String?)?.trim() ?? '',
      workEmailLower:
          (data['workEmailLower'] as String?)?.trim().toLowerCase() ??
          docId.trim().toLowerCase(),
      domain: (data['domain'] as String?)?.trim().toLowerCase() ?? '',
      workspaceIds: ids,
      updatedAt: _ts(data['updatedAt']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  @override
  List<Object?> get props => [uid, workEmailLower, domain, workspaceIds];
}
