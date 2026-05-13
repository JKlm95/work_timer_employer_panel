import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../core/utils/tracked_workspace_policy.dart';

/// Row in `employers/{employerUid}/trackedWorkspaces/{accessId}`.
class TrackedWorkspaceAccess extends Equatable {
  const TrackedWorkspaceAccess({
    required this.accessId,
    required this.employeeUid,
    required this.workspaceId,
    required this.employeeEmailLower,
    required this.companyName,
    required this.companySlug,
    required this.workspaceName,
    this.createdAt,
    this.updatedAt,
  });

  final String accessId;
  final String employeeUid;
  final String workspaceId;
  final String employeeEmailLower;
  final String companyName;
  final String companySlug;
  final String workspaceName;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory TrackedWorkspaceAccess.fromDoc(String id, Map<String, dynamic> d) {
    return TrackedWorkspaceAccess(
      accessId: id,
      employeeUid: (d['employeeUid'] as String?)?.trim() ?? '',
      workspaceId: (d['workspaceId'] as String?)?.trim() ?? '',
      employeeEmailLower: (d['employeeEmailLower'] as String?)?.trim() ?? '',
      companyName: (d['companyName'] as String?)?.trim() ?? '',
      companySlug: (d['companySlug'] as String?)?.trim() ?? '',
      workspaceName: (d['workspaceName'] as String?)?.trim() ?? '',
      createdAt: _ts(d['createdAt']),
      updatedAt: _ts(d['updatedAt']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  Map<String, dynamic> toWriteMap() {
    return {
      'employeeUid': employeeUid,
      'workspaceId': workspaceId,
      'employeeEmailLower': employeeEmailLower,
      'companyName': companyName,
      'companySlug': companySlug,
      'workspaceName': workspaceName,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toMergePatch() {
    return {
      'employeeUid': employeeUid,
      'workspaceId': workspaceId,
      'employeeEmailLower': employeeEmailLower,
      'companyName': companyName,
      'companySlug': companySlug,
      'workspaceName': workspaceName,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  static String docIdFor(String employeeUid, String workspaceId) =>
      trackedWorkspaceAccessDocId(employeeUid, workspaceId);

  @override
  List<Object?> get props => [accessId, workspaceId, employeeUid];
}
