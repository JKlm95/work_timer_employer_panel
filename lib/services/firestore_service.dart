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
/// **MVP writes:** The only mutations allowed on employee-owned data from this panel are
/// [updateWorkspaceBilling] (`hourlyRate`, `currency` on `users/{uid}/workspaces/{id}`).
/// Tracked employees and groups live under `employers/{employerUid}/…`.
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
      final list = s.docs.map((d) => TrackedEmployee.fromDoc(d.id, d.data())).toList();
      list.sort((a, b) {
        final ad = a.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.addedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
        final c = bd.compareTo(ad);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });
      return list;
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

  Map<String, dynamic> _nameFieldsFromIndex(UserEmailIndex index) {
    final m = <String, dynamic>{};
    final fn = index.firstName?.trim();
    final ln = index.lastName?.trim();
    final dn = index.displayName?.trim();
    if (fn != null && fn.isNotEmpty) m['firstName'] = fn;
    if (ln != null && ln.isNotEmpty) m['lastName'] = ln;
    if (dn != null && dn.isNotEmpty) m['displayName'] = dn;
    return m;
  }

  Map<String, dynamic> _mergeNameFieldsIfMissing(Map<String, dynamic> existing, UserEmailIndex index) {
    final patch = <String, dynamic>{};
    bool missing(String k) {
      final s = existing[k];
      if (s == null) return true;
      if (s is String && s.trim().isEmpty) return true;
      return false;
    }

    void fill(String key, String? fromIndex) {
      final v = fromIndex?.trim();
      if (v == null || v.isEmpty) return;
      if (missing(key)) patch[key] = v;
    }

    fill('firstName', index.firstName);
    fill('lastName', index.lastName);
    fill('displayName', index.displayName);
    return patch;
  }

  Map<String, dynamic> _overwriteNameFieldsFromIndexWhereProvided(
    Map<String, dynamic> existing,
    UserEmailIndex index,
  ) {
    final patch = <String, dynamic>{};
    void consider(String key, String? fromIndex) {
      final v = fromIndex?.trim();
      if (v == null || v.isEmpty) return;
      final cur = existing[key];
      final curStr = cur is String ? cur.trim() : '';
      if (curStr != v) patch[key] = v;
    }

    consider('firstName', index.firstName);
    consider('lastName', index.lastName);
    consider('displayName', index.displayName);
    return patch;
  }

  /// Pulls latest name fields from `userEmailIndex` into one `trackedEmployees` doc (when index has data).
  Future<bool> syncTrackedEmployeeProfileFromIndex(String employerUid, String trackedDocId) async {
    final ref = _employerTracked(employerUid).doc(trackedDocId);
    final d = await ref.get();
    if (!d.exists || d.data() == null) return false;
    final emailLower = d.data()!['employeeEmailLower'] as String?;
    if (emailLower == null || emailLower.isEmpty) return false;
    final idx = await getUserEmailIndex(emailLower);
    if (idx == null) return false;
    final patch = _overwriteNameFieldsFromIndexWhereProvided(d.data()!, idx);
    if (patch.isEmpty) return false;
    await ref.update(patch);
    return true;
  }

  /// Refreshes every tracked employee from `userEmailIndex`. Returns how many docs were updated.
  Future<int> syncTrackedEmployeeProfilesFromIndex(String employerUid) async {
    final snap = await _employerTracked(employerUid).get();
    var n = 0;
    for (final d in snap.docs) {
      final emailLower = d.data()['employeeEmailLower'] as String?;
      if (emailLower == null || emailLower.isEmpty) continue;
      final idx = await getUserEmailIndex(emailLower);
      if (idx == null) continue;
      final patch = _overwriteNameFieldsFromIndexWhereProvided(d.data(), idx);
      if (patch.isEmpty) continue;
      await d.reference.update(patch);
      n++;
    }
    return n;
  }

  /// **TODO (mobile):** If the app always writes `end` on entries, this stream never fires — add
  /// `liveStatus` (or equivalent) later. Until then, "Working" = at least one non-deleted entry
  /// with `end == null`.
  Stream<bool> hasOpenTimerStream(String employeeUid) {
    return _db
        .collection('users')
        .doc(employeeUid)
        .collection('entries')
        .where('isDeleted', isEqualTo: false)
        .where('end', isNull: true)
        .limit(1)
        .snapshots()
        .map((s) => s.docs.isNotEmpty);
  }

  /// One-shot check (e.g. dashboard aggregates). See [hasOpenTimerStream] for TODO on mobile `end`.
  Future<bool> hasOpenTimer(String employeeUid) async {
    final q = await _db
        .collection('users')
        .doc(employeeUid)
        .collection('entries')
        .where('isDeleted', isEqualTo: false)
        .where('end', isNull: true)
        .limit(1)
        .get();
    return q.docs.isNotEmpty;
  }

  /// Prefer `updatedAt`, fallback `start`, on newest non-deleted entry.
  Future<DateTime?> fetchLastActivityAt(String employeeUid) async {
    try {
      final snap = await _db
          .collection('users')
          .doc(employeeUid)
          .collection('entries')
          .where('isDeleted', isEqualTo: false)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      final e = WorkEntry.fromDoc(snap.docs.first.id, snap.docs.first.data());
      return e.updatedAt ?? e.start;
    } catch (_) {
      final snap = await _db
          .collection('users')
          .doc(employeeUid)
          .collection('entries')
          .orderBy('start', descending: true)
          .limit(40)
          .get();
      DateTime? best;
      for (final d in snap.docs) {
        final e = WorkEntry.fromDoc(d.id, d.data());
        if (e.isDeleted) continue;
        final ts = e.updatedAt ?? e.start;
        if (best == null || ts.isAfter(best)) best = ts;
      }
      return best;
    }
  }

  /// **MVP:** Employer may update billing fields on the employee workspace document.
  /// **TODO (mobile):** Firestore is source of truth; ensure the mobile client merges server writes
  /// instead of overwriting with stale local cache after employer edits.
  Future<void> updateWorkspaceBilling({
    required String employeeUid,
    required String workspaceId,
    required double hourlyRate,
    required String currency,
  }) async {
    if (hourlyRate < 0 || hourlyRate > 99999) {
      throw WorkspaceBillingException('Rate must be between 0 and 99,999.');
    }
    final c = currency.trim().toUpperCase();
    const allowed = {'PLN', 'EUR', 'USD', 'GBP'};
    if (!allowed.contains(c)) {
      throw WorkspaceBillingException('Currency must be PLN, EUR, USD, or GBP.');
    }
    await _db.collection('users').doc(employeeUid).collection('workspaces').doc(workspaceId).update({
      'hourlyRate': hourlyRate,
      'currency': c,
      'updatedAt': FieldValue.serverTimestamp(),
    });
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
      final doc = existing.docs.first;
      final mergePatch = _mergeNameFieldsIfMissing(doc.data(), index);
      if (mergePatch.isNotEmpty) {
        await doc.reference.update(mergePatch);
      }
      throw EmployerLinkException('This employee is already on your list for this company.');
    }

    final nameFields = _nameFieldsFromIndex(index);
    await _employerTracked(employerUid).add({
      'employeeUid': index.uid,
      'employeeEmail': employeeWorkEmailInput.trim(),
      'employeeEmailLower': employeeEmailLower,
      ...nameFields,
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

class WorkspaceBillingException implements Exception {
  WorkspaceBillingException(this.message);
  final String message;

  @override
  String toString() => message;
}
