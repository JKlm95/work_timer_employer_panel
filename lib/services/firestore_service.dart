import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/utils/company_slug_utils.dart';
import '../core/utils/email_domain_utils.dart';
import '../core/utils/report_period.dart';
import '../models/employer_group.dart';
import '../models/tracked_employee.dart';
import '../models/user_email_index.dart';
import '../models/work_entry.dart';
import '../models/workspace.dart';

/// Firestore access for the employer panel.
///
/// **Security:** Reads under `users/{uid}/...` assume Firestore rules eventually allow
/// constrained access (e.g. only after employer–employee relationship exists). Do **not**
/// ship production rules that expose all user documents. Functions or strict rules are
/// needed for a hardened deployment — see `firestore.rules`.
class FirestoreService {
  FirestoreService({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> _employerTracked(String employerUid) =>
      _db.collection('employers').doc(employerUid).collection('trackedEmployees');

  CollectionReference<Map<String, dynamic>> _employerGroups(String employerUid) =>
      _db.collection('employers').doc(employerUid).collection('groups');

  /// **TODO (mobile app):** Maintain `userEmailIndex/{emailLower}` after login so lookups work.
  Future<UserEmailIndex?> getUserEmailIndex(String emailLower) async {
    final doc = await _db.collection('userEmailIndex').doc(emailLower).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserEmailIndex.fromDoc(doc.id, doc.data()!);
  }

  /// Reads employee workspaces — sensitive; gated by rules in production.
  Future<List<Workspace>> fetchEmployeeWorkspaces(String employeeUid) async {
    final snap = await _db.collection('users').doc(employeeUid).collection('workspaces').get();
    return snap.docs.map((d) => Workspace.fromDoc(d.id, d.data())).toList();
  }

  /// Reads employee time entries in `[start, end]` by `start` field (MVP query).
  ///
  /// Composite index may be required: `entries` collection — `start` ASC + optional filters.
  Future<List<WorkEntry>> fetchEntriesInRange(
    String employeeUid,
    ReportPeriod period,
  ) async {
    final startTs = Timestamp.fromDate(period.start);
    final endTs = Timestamp.fromDate(period.endInclusive);
    final ref = _db.collection('users').doc(employeeUid).collection('entries');
    Query<Map<String, dynamic>> q = ref
        .where('start', isGreaterThanOrEqualTo: startTs)
        .where('start', isLessThanOrEqualTo: endTs);
    final snap = await q.get();
    return snap.docs.map((d) => WorkEntry.fromDoc(d.id, d.data())).toList();
  }

  Stream<List<TrackedEmployee>> trackedEmployeesStream(String employerUid) {
    return _employerTracked(employerUid).snapshots().map((s) {
      return s.docs.map((d) => TrackedEmployee.fromDoc(d.id, d.data())).toList();
    });
  }

  Stream<List<EmployerGroup>> groupsStream(String employerUid) {
    return _employerGroups(employerUid).orderBy('name').snapshots().map((s) {
      return s.docs.map((d) => EmployerGroup.fromDoc(d.id, d.data())).toList();
    });
  }

  Future<void> createGroup(String employerUid, {required String name, required String colorHex}) async {
    final doc = _employerGroups(employerUid).doc();
    await doc.set({
      'name': name,
      'colorHex': colorHex,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> updateGroup(
    String employerUid,
    String groupId, {
    required String name,
    required String colorHex,
  }) async {
    await _employerGroups(employerUid).doc(groupId).update({
      'name': name,
      'colorHex': colorHex,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  Future<void> deleteGroup(String employerUid, String groupId) async {
    await _employerGroups(employerUid).doc(groupId).delete();
    final tracked = await _employerTracked(employerUid).get();
    for (final d in tracked.docs) {
      final data = d.data();
      final ids = (data['groupIds'] as List?)?.map((e) => e.toString()).toList() ?? <String>[];
      if (ids.contains(groupId)) {
        await d.reference.update({
          'groupIds': FieldValue.arrayRemove([groupId]),
        });
      }
    }
  }

  Future<void> setTrackedEmployeeGroups(
    String employerUid,
    String trackedId,
    List<String> groupIds,
  ) async {
    await _employerTracked(employerUid).doc(trackedId).update({'groupIds': groupIds});
  }

  Future<void> removeTrackedEmployee(String employerUid, String trackedId) async {
    await _employerTracked(employerUid).doc(trackedId).delete();
  }

  /// Validates domain + workspace match, then writes `trackedEmployees` doc.
  Future<void> linkEmployee({
    required String employerUid,
    required String employerEmail,
    required String employeeWorkEmailInput,
    required String companyNameInput,
  }) async {
    final employerDomain = emailDomain(employerEmail);
    if (employerDomain == null) {
      throw EmployerLinkException(
        'Employer email domain does not match employee work email domain',
      );
    }

    final employeeEmailLower = employeeWorkEmailInput.trim().toLowerCase();
    final normalizedSlug = normalizeCompanySlugInput(companyNameInput);
    if (normalizedSlug.isEmpty) {
      throw EmployerLinkException('No shared project found for this company');
    }

    final index = await getUserEmailIndex(employeeEmailLower);
    if (index == null || index.uid.isEmpty) {
      throw EmployerLinkException('Employee not found');
    }

    final workspaces = await fetchEmployeeWorkspaces(index.uid);
    Workspace? matched;
    for (final w in workspaces) {
      final wEmail = w.employeeWorkEmail?.trim().toLowerCase();
      final wSlug = (w.companySlug ?? '').trim().toLowerCase();
      if (wEmail == employeeEmailLower && wSlug == normalizedSlug) {
        matched = w;
        break;
      }
    }

    if (matched == null) {
      throw EmployerLinkException('No shared project found for this company');
    }

    final wsDomain = matched.employeeWorkEmailDomain?.trim().toLowerCase();
    if (wsDomain == null || wsDomain.isEmpty || wsDomain != employerDomain) {
      throw EmployerLinkException(
        'Employer email domain does not match employee work email domain',
      );
    }

    final existing = await _employerTracked(employerUid).where('employeeUid', isEqualTo: index.uid).where(
      'companySlug',
      isEqualTo: normalizedSlug,
    ).limit(1).get();

    if (existing.docs.isNotEmpty) {
      throw EmployerLinkException('This employee is already on your list for this company.');
    }

    await _employerTracked(employerUid).add({
      'employeeUid': index.uid,
      'employeeEmail': employeeWorkEmailInput.trim(),
      'employeeEmailLower': employeeEmailLower,
      'displayName': index.displayName,
      'companyName': matched.companyName ?? companyNameInput.trim(),
      'companySlug': normalizedSlug,
      'addedAt': FieldValue.serverTimestamp(),
      'groupIds': <String>[],
    });
  }
}

class EmployerLinkException implements Exception {
  EmployerLinkException(this.message);
  final String message;

  @override
  String toString() => message;
}
