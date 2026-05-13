import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/debug/live_status_debug_config.dart';
import '../core/utils/company_slug_utils.dart';
import '../core/utils/email_domain_utils.dart';
import '../core/utils/employee_presence_utils.dart';
import '../core/utils/report_period.dart';
import '../models/employee_live_status.dart';
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

  CollectionReference<Map<String, dynamic>> _employerTracked(
    String employerUid,
  ) => _db
      .collection('employers')
      .doc(employerUid)
      .collection('trackedEmployees');

  CollectionReference<Map<String, dynamic>> _employerGroups(
    String employerUid,
  ) => _db.collection('employers').doc(employerUid).collection('groups');

  CollectionReference<Map<String, dynamic>> _employerTrackedEmployeeUids(
    String employerUid,
  ) => _db
      .collection('employers')
      .doc(employerUid)
      .collection('trackedEmployeeUids');

  /// One doc per `employeeUid` so rules can grant `users/{employeeUid}/live/status` to this employer.
  Future<void> _setTrackedEmployeeUidAccess(
    String employerUid,
    String employeeUid,
  ) async {
    final uid = employeeUid.trim();
    if (uid.isEmpty) return;
    await _employerTrackedEmployeeUids(employerUid).doc(uid).set({
      'employeeUid': uid,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Backfill [trackedEmployeeUids] for employers who linked employees before this collection existed.
  Future<void> ensureTrackedEmployeeUidAccessDocs(String employerUid) async {
    final snap = await _employerTracked(employerUid).get();
    for (final d in snap.docs) {
      final uid = d.data()['employeeUid'] as String?;
      if (uid == null || uid.trim().isEmpty) continue;
      await _setTrackedEmployeeUidAccess(employerUid, uid);
    }
  }

  /// `users/{employeeUid}/live/status` — mobile presence / timer.
  Stream<EmployeeLiveStatus?> employeeLiveStatusStream(String employeeUid) {
    return _db
        .collection('users')
        .doc(employeeUid)
        .collection('live')
        .doc('status')
        .snapshots()
        .map((s) {
          try {
            if (!s.exists) {
              if (kDebugMode && LiveStatusDebugConfig.verboseLiveLogs) {
                debugPrint('[LiveStatus] uid=$employeeUid no document');
              }
              return null;
            }
            final data = s.data();
            if (data == null) return null;
            final r = EmployeeLiveStatus.fromMap(data);
            if (kDebugMode && LiveStatusDebugConfig.verboseLiveLogs) {
              final presence = resolveWorkPresence(live: r);
              final secs = r.currentAccumulatedSeconds(DateTime.now());
              debugPrint(
                '[LiveStatus] uid=$employeeUid timerState=${r.timerState} isOnline=${r.isOnline} '
                'activeWorkspaceId=${r.activeWorkspaceId} activeCompanySlug=${r.activeCompanySlug} '
                'hourlyRate=${r.hourlyRate} currency=${r.currency} lastSeenAt=${r.lastSeenAt} updatedAt=${r.updatedAt} '
                '=> presence=$presence accumulatedSeconds=$secs',
              );
            }
            return r;
          } catch (e, st) {
            if (kDebugMode) {
              debugPrint('[LiveStatus] parse error uid=$employeeUid $e\n$st');
            }
            return null;
          }
        });
  }

  Future<EmployeeLiveStatus?> fetchEmployeeLiveStatus(
    String employeeUid,
  ) async {
    try {
      final doc = await _db
          .collection('users')
          .doc(employeeUid)
          .collection('live')
          .doc('status')
          .get();
      if (!doc.exists) return null;
      final data = doc.data();
      if (data == null) return null;
      return EmployeeLiveStatus.fromMap(data);
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[LiveStatus] fetch error uid=$employeeUid $e\n$st');
      }
      return null;
    }
  }

  /// **TODO (mobile app):** Maintain `userEmailIndex/{emailLower}` after login so lookups work.
  Future<UserEmailIndex?> getUserEmailIndex(String emailLower) async {
    final doc = await _db.collection('userEmailIndex').doc(emailLower).get();
    if (!doc.exists || doc.data() == null) return null;
    return UserEmailIndex.fromDoc(doc.id, doc.data()!);
  }

  /// Reads employee workspaces — sensitive; gated by rules in production.
  Future<List<Workspace>> fetchEmployeeWorkspaces(
    String employeeUid, {
    bool preferServer = false,
  }) async {
    final opts = GetOptions(
      source: preferServer ? Source.server : Source.serverAndCache,
    );
    final snap = await _db
        .collection('users')
        .doc(employeeUid)
        .collection('workspaces')
        .get(opts);
    return snap.docs.map((d) => Workspace.fromDoc(d.id, d.data())).toList();
  }

  /// Reads employee time entries in `[start, end]` by `start` field (MVP query).
  ///
  /// Composite index may be required: `entries` collection — `start` ASC + optional filters.
  Future<List<WorkEntry>> fetchEntriesInRange(
    String employeeUid,
    ReportPeriod period, {
    bool preferServer = false,
  }) async {
    final startTs = Timestamp.fromDate(period.start);
    final endTs = Timestamp.fromDate(period.endInclusive);
    final ref = _db.collection('users').doc(employeeUid).collection('entries');
    Query<Map<String, dynamic>> q = ref
        .where('start', isGreaterThanOrEqualTo: startTs)
        .where('start', isLessThanOrEqualTo: endTs);
    final opts = GetOptions(
      source: preferServer ? Source.server : Source.serverAndCache,
    );
    final snap = await q.get(opts);
    return snap.docs.map((d) => WorkEntry.fromDoc(d.id, d.data())).toList();
  }

  /// Live updates when any entry in [period] (by `start`) changes for [employeeUid].
  Stream<QuerySnapshot<Map<String, dynamic>>> entriesInMonthSnapshots(
    String employeeUid,
    ReportPeriod period,
  ) {
    final startTs = Timestamp.fromDate(period.start);
    final endTs = Timestamp.fromDate(period.endInclusive);
    return _db
        .collection('users')
        .doc(employeeUid)
        .collection('entries')
        .where('start', isGreaterThanOrEqualTo: startTs)
        .where('start', isLessThanOrEqualTo: endTs)
        .snapshots();
  }

  /// Each emission re-reads `userEmailIndex/{employeeEmailLower}` so names stay in sync with mobile
  /// without relying on workspace or stale `trackedEmployees` copies (see [TrackedEmployee.mergedWithUserEmailIndex]).
  Stream<List<TrackedEmployee>> trackedEmployeesStream(String employerUid) {
    return _employerTracked(employerUid).snapshots().asyncMap((s) async {
      final list = <TrackedEmployee>[];
      for (final d in s.docs) {
        final base = TrackedEmployee.fromDoc(d.id, d.data());
        final idx = await getUserEmailIndex(base.employeeEmailLower);
        list.add(base.mergedWithUserEmailIndex(idx));
      }
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

  Future<void> createGroup(
    String employerUid, {
    required String name,
    required String colorHex,
  }) async {
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
      final ids =
          (data['groupIds'] as List?)?.map((e) => e.toString()).toList() ??
          <String>[];
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
    await _employerTracked(
      employerUid,
    ).doc(trackedId).update({'groupIds': groupIds});
  }

  Future<void> removeTrackedEmployee(
    String employerUid,
    String trackedId,
  ) async {
    final ref = _employerTracked(employerUid).doc(trackedId);
    final snap = await ref.get();
    final removedUid = snap.data()?['employeeUid'] as String?;
    await ref.delete();
    if (removedUid != null && removedUid.trim().isNotEmpty) {
      final others = await _employerTracked(
        employerUid,
      ).where('employeeUid', isEqualTo: removedUid).limit(1).get();
      if (others.docs.isEmpty) {
        await _employerTrackedEmployeeUids(
          employerUid,
        ).doc(removedUid.trim()).delete();
      }
    }
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

  /// Identity + name fields stored on `trackedEmployees` — all sourced from [UserEmailIndex].
  Map<String, dynamic> _personalEmployeeWriteMap(
    UserEmailIndex index, {
    required String employeeEmailFallback,
    required String emailLowerFallback,
  }) {
    return {
      'employeeUid': index.uid.trim(),
      'employeeEmail': index.email.trim().isNotEmpty
          ? index.email.trim()
          : employeeEmailFallback,
      'employeeEmailLower': index.emailLower.trim().isNotEmpty
          ? index.emailLower.trim().toLowerCase()
          : emailLowerFallback,
      ..._nameFieldsFromIndex(index),
    };
  }

  Map<String, dynamic> _personalEmployeePatchFromIndex(
    UserEmailIndex index,
    Map<String, dynamic> existing,
  ) {
    final desired = _personalEmployeeWriteMap(
      index,
      employeeEmailFallback:
          (existing['employeeEmail'] as String?)?.trim() ?? '',
      emailLowerFallback:
          (existing['employeeEmailLower'] as String?)?.trim().toLowerCase() ??
          '',
    );
    final patch = <String, dynamic>{};
    for (final e in desired.entries) {
      final key = e.key;
      final v = e.value;
      final cur = existing[key];
      final curNorm = cur == null
          ? ''
          : cur is String
          ? cur.trim()
          : cur.toString();
      final newNorm = v is String ? v.trim() : v.toString();
      if (curNorm != newNorm) patch[key] = v;
    }
    return patch;
  }

  /// Pulls latest personal fields from `userEmailIndex` into one `trackedEmployees` doc.
  Future<bool> syncTrackedEmployeeProfileFromIndex(
    String employerUid,
    String trackedDocId,
  ) async {
    final ref = _employerTracked(employerUid).doc(trackedDocId);
    final d = await ref.get();
    if (!d.exists || d.data() == null) return false;
    final emailLower = d.data()!['employeeEmailLower'] as String?;
    if (emailLower == null || emailLower.isEmpty) return false;
    final idx = await getUserEmailIndex(emailLower);
    if (idx == null) return false;
    final patch = _personalEmployeePatchFromIndex(idx, d.data()!);
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
      final patch = _personalEmployeePatchFromIndex(idx, d.data());
      if (patch.isEmpty) continue;
      await d.reference.update(patch);
      n++;
    }
    return n;
  }

  /// **Legacy:** open entry with `end == null`. Prefer [employeeLiveStatusStream] for UI presence.
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
  Future<DateTime?> fetchLastActivityAt(
    String employeeUid, {
    bool preferServer = false,
  }) async {
    final opts = GetOptions(
      source: preferServer ? Source.server : Source.serverAndCache,
    );
    try {
      final snap = await _db
          .collection('users')
          .doc(employeeUid)
          .collection('entries')
          .where('isDeleted', isEqualTo: false)
          .orderBy('updatedAt', descending: true)
          .limit(1)
          .get(opts);
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
          .get(opts);
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
      throw WorkspaceBillingException(
        'Currency must be PLN, EUR, USD, or GBP.',
      );
    }
    await _db
        .collection('users')
        .doc(employeeUid)
        .collection('workspaces')
        .doc(workspaceId)
        .update({
          'hourlyRate': hourlyRate,
          'currency': c,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  /// Validates domain + workspace match (company/slug only — not names), then writes `trackedEmployees`.
  /// Personal fields on the new doc come only from [getUserEmailIndex].
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

    final existing = await _employerTracked(employerUid)
        .where('employeeUid', isEqualTo: index.uid)
        .where('companySlug', isEqualTo: normalizedSlug)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      final doc = existing.docs.first;
      final patch = _personalEmployeePatchFromIndex(index, doc.data());
      if (patch.isNotEmpty) {
        await doc.reference.update(patch);
      }
      await _setTrackedEmployeeUidAccess(employerUid, index.uid.trim());
      throw EmployerLinkException(
        'This employee is already on your list for this company.',
      );
    }

    await _employerTracked(employerUid).add({
      ..._personalEmployeeWriteMap(
        index,
        employeeEmailFallback: employeeWorkEmailInput.trim(),
        emailLowerFallback: employeeEmailLower,
      ),
      'companyName': matched.companyName ?? companyNameInput.trim(),
      'companySlug': normalizedSlug,
      'addedAt': FieldValue.serverTimestamp(),
      'groupIds': <String>[],
    });
    await _setTrackedEmployeeUidAccess(employerUid, index.uid.trim());
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
