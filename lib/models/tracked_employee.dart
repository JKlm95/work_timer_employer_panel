import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Employer-side link to an employee — stored under `employers/{employerUid}/trackedEmployees`.
class TrackedEmployee extends Equatable {
  const TrackedEmployee({
    required this.id,
    required this.employeeUid,
    required this.employeeEmail,
    required this.employeeEmailLower,
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
  final String? displayName;
  final String companyName;
  final String companySlug;
  final DateTime? addedAt;
  final List<String> groupIds;

  factory TrackedEmployee.fromDoc(String id, Map<String, dynamic> data) {
    final groups = data['groupIds'];
    return TrackedEmployee(
      id: id,
      employeeUid: data['employeeUid'] as String? ?? '',
      employeeEmail: data['employeeEmail'] as String? ?? '',
      employeeEmailLower: data['employeeEmailLower'] as String? ?? '',
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
