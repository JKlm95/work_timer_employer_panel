import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Employer-side link to an employee — stored under `employers/{employerUid}/trackedEmployees`.
///
/// Name fields are copied from `userEmailIndex` when linking and can be refreshed via
/// [FirestoreService.syncTrackedEmployeeProfilesFromIndex].
class TrackedEmployee extends Equatable {
  const TrackedEmployee({
    required this.id,
    required this.employeeUid,
    required this.employeeEmail,
    required this.employeeEmailLower,
    this.firstName,
    this.lastName,
    this.displayName,
    required this.companyName,
    required this.companySlug,
    this.addedAt,
    this.groupIds = const [],
  });

  final String id;
  final String employeeUid;
  final String employeeEmail;
  final String employeeEmailLower;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final String companyName;
  final String companySlug;
  final DateTime? addedAt;
  final List<String> groupIds;

  /// Primary display name: `firstName` + `lastName`, else `displayName`, else email.
  String get fullName {
    final fn = firstName?.trim() ?? '';
    final ln = lastName?.trim() ?? '';
    if (fn.isNotEmpty || ln.isNotEmpty) {
      return '$fn $ln'.trim();
    }
    final d = displayName?.trim();
    if (d != null && d.isNotEmpty) return d;
    return employeeEmail;
  }

  factory TrackedEmployee.fromDoc(String id, Map<String, dynamic> data) {
    final groups = data['groupIds'];
    return TrackedEmployee(
      id: id,
      employeeUid: data['employeeUid'] as String? ?? '',
      employeeEmail: data['employeeEmail'] as String? ?? '',
      employeeEmailLower: data['employeeEmailLower'] as String? ?? '',
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      displayName: data['displayName'] as String?,
      companyName: data['companyName'] as String? ?? '',
      companySlug: data['companySlug'] as String? ?? '',
      addedAt: _ts(data['addedAt']),
      groupIds: groups is List ? groups.map((e) => e.toString()).toList() : const [],
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  @override
  List<Object?> get props => [id];
}
