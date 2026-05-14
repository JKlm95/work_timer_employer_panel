import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

import '../core/utils/employer_group_ids_utils.dart';
import 'user_email_index.dart';

/// Employer-side link to an employee — stored under `employers/{employerUid}/trackedEmployees`.
///
/// Linking is by **employee work email** (see `employeeWorkEmailLower` / `employeeWorkEmailDomain`).
/// Personal fields are merged from [UserEmailIndex] when keyed by the same lowercased email
/// ([mergedWithUserEmailIndex]).
class TrackedEmployee extends Equatable {
  const TrackedEmployee({
    required this.id,
    required this.employeeUid,
    required this.employeeEmail,
    required this.employeeEmailLower,
    required this.employeeWorkEmailLower,
    required this.employeeWorkEmailDomain,
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

  /// Work email used for `employeeWorkEmailIndex` / workspace sharing (lowercase).
  final String employeeWorkEmailLower;

  /// Domain of [employeeWorkEmailLower] (lowercase), e.g. `firma.pl`.
  final String employeeWorkEmailDomain;

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

  /// Overlay for UI: when [index] is non-null, personal fields come **only** from the index
  /// (never from workspace). When [index] is null, returns `this` (Firestore snapshot).
  TrackedEmployee mergedWithUserEmailIndex(UserEmailIndex? index) {
    if (index == null) return this;
    String nz(String s) => s.trim();
    String? opt(String? s) {
      final t = nz(s ?? '');
      return t.isEmpty ? null : t;
    }

    return TrackedEmployee(
      id: id,
      employeeUid: nz(index.uid).isNotEmpty ? index.uid.trim() : employeeUid,
      employeeEmail: nz(index.email).isNotEmpty
          ? index.email.trim()
          : employeeEmail,
      employeeEmailLower: nz(index.emailLower).isNotEmpty
          ? index.emailLower.trim().toLowerCase()
          : employeeEmailLower,
      employeeWorkEmailLower: employeeWorkEmailLower,
      employeeWorkEmailDomain: employeeWorkEmailDomain,
      firstName: opt(index.firstName),
      lastName: opt(index.lastName),
      displayName: opt(index.displayName),
      companyName: companyName,
      companySlug: companySlug,
      addedAt: addedAt,
      groupIds: groupIds,
    );
  }

  factory TrackedEmployee.fromDoc(String id, Map<String, dynamic> data) {
    final emailLower =
        (data['employeeEmailLower'] as String?)?.trim().toLowerCase() ?? '';
    final workLower =
        (data['employeeWorkEmailLower'] as String?)?.trim().toLowerCase() ??
        emailLower;
    final workDomain =
        (data['employeeWorkEmailDomain'] as String?)?.trim().toLowerCase() ??
        '';
    return TrackedEmployee(
      id: id,
      employeeUid: data['employeeUid'] as String? ?? '',
      employeeEmail: data['employeeEmail'] as String? ?? '',
      employeeEmailLower: emailLower,
      employeeWorkEmailLower: workLower,
      employeeWorkEmailDomain: workDomain,
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      displayName: data['displayName'] as String?,
      companyName: data['companyName'] as String? ?? '',
      companySlug: data['companySlug'] as String? ?? '',
      addedAt: _ts(data['addedAt']),
      groupIds: parseAndDedupeGroupIds(data['groupIds']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  @override
  List<Object?> get props => [id];
}
