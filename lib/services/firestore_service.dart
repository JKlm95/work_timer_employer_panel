import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../core/debug/live_status_debug_config.dart';
import '../core/utils/company_slug_utils.dart';
import '../core/utils/employer_entry_soft_patch.dart';
import '../core/utils/email_domain_utils.dart';
import '../core/utils/employee_presence_utils.dart';
import '../core/utils/employer_workspace_query_utils.dart';
import '../core/utils/report_period.dart';
import '../models/employee_live_status.dart';
import '../models/employer_group.dart';
import '../core/utils/tracked_workspace_policy.dart' as twp;
import '../models/tracked_employee.dart';
import '../models/tracked_workspace_access.dart';
import '../models/user_email_index.dart';
import '../models/work_entry.dart';
import '../models/workspace.dart';

/// Firestore access for the employer panel.
///
/// **MVP writes on employee data:** [updateWorkspaceBilling] on workspaces, and
/// employer-authored **time entries** under `users/{uid}/entries` (see [createEmployeeEntry]).
/// Tracked employees and groups live under `employers/{employerUid}/…`.
///
/// **Security:** Reads under `users/{uid}/...` assume Firestore rules allow employer access
/// only for **`trackedWorkspaces`** (entries + billing) and **`trackedEmployeeUids`** (e.g. `live/status`),
/// plus shared-workspace listing where applicable — see `firestore.rules`.
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

  CollectionReference<Map<String, dynamic>> _employerTrackedWorkspaces(
    String employerUid,
  ) => _db
      .collection('employers')
      .doc(employerUid)
      .collection('trackedWorkspaces');

  void _logEmployerEntriesDebug(
    String op, {
    required String employerUid,
    required String employeeUid,
    required Set<String> workspaceIds,
    required int chunkCount,
    String? extra,
  }) {
    if (!kDebugMode) return;
    debugPrint(
      '[EmployerFS/$op] employer=$employerUid employee=$employeeUid '
      'trackedWsCount=${workspaceIds.length} chunks=$chunkCount${extra != null ? ' $extra' : ''}',
    );
  }

  /// Workspace-level access for this employer (real data scope for the panel).
  Future<List<TrackedWorkspaceAccess>> fetchTrackedWorkspaces(
    String employerUid,
  ) async {
    final snap = await _employerTrackedWorkspaces(employerUid).get();
    final raw = snap.docs
        .map((d) => TrackedWorkspaceAccess.fromDoc(d.id, d.data()))
        .toList();
    return dedupeTrackedWorkspaceAccessDocs(raw);
  }

  Stream<List<TrackedWorkspaceAccess>> trackedWorkspaceAccessStream(
    String employerUid,
  ) {
    return _employerTrackedWorkspaces(employerUid).snapshots().map((s) {
      final raw = s.docs
          .map((d) => TrackedWorkspaceAccess.fromDoc(d.id, d.data()))
          .toList();
      return dedupeTrackedWorkspaceAccessDocs(raw);
    });
  }

  Future<Set<String>> trackedWorkspaceIdsForEmployee(
    String employerUid,
    String employeeUid,
  ) async {
    final all = await fetchTrackedWorkspaces(employerUid);
    final uid = employeeUid.trim();
    return normalizedWorkspaceIdSet(
      all.where((a) => a.employeeUid == uid).map((a) => a.workspaceId),
    );
  }

  Future<bool> employerCanAccessWorkspace(
    String employerUid,
    String employeeUid,
    String workspaceId,
  ) async {
    final id = TrackedWorkspaceAccess.docIdFor(employeeUid, workspaceId);
    final d = await _employerTrackedWorkspaces(employerUid).doc(id).get();
    return d.exists;
  }

  List<WorkEntry> filterEntriesByTrackedWorkspaces(
    Iterable<WorkEntry> entries,
    Set<String> allowedWorkspaceIds,
  ) => twp.filterEntriesByTrackedWorkspaces(entries, allowedWorkspaceIds);

  /// Creates or merges one `trackedWorkspaces` row (e.g. admin / repair).
  Future<void> ensureTrackedWorkspaceAccess({
    required String employerUid,
    required String employeeUid,
    required String workspaceId,
    required String employeeEmailLower,
    required String companyName,
    required String companySlug,
    required String workspaceName,
  }) async {
    final id = TrackedWorkspaceAccess.docIdFor(employeeUid, workspaceId);
    final ref = _employerTrackedWorkspaces(employerUid).doc(id);
    final cur = await ref.get();
    final access = TrackedWorkspaceAccess(
      accessId: id,
      employeeUid: employeeUid.trim(),
      workspaceId: workspaceId.trim(),
      employeeEmailLower: employeeEmailLower.trim().toLowerCase(),
      companyName: companyName.trim(),
      companySlug: companySlug.trim(),
      workspaceName: workspaceName.trim(),
    );
    if (cur.exists) {
      await ref.set(access.toMergePatch(), SetOptions(merge: true));
    } else {
      await ref.set(access.toWriteMap());
    }
  }

  Future<void> _deleteAllTrackedWorkspacesForEmployee(
    String employerUid,
    String employeeUid,
  ) async {
    final uid = employeeUid.trim();
    if (uid.isEmpty) return;
    final snap = await _employerTrackedWorkspaces(
      employerUid,
    ).where('employeeUid', isEqualTo: uid).get();
    for (final d in snap.docs) {
      await d.reference.delete();
    }
  }

  Future<void> _replaceTrackedWorkspacesForEmployee(
    String employerUid,
    String employeeUid,
    Set<TrackedWorkspaceAccess> desired,
  ) async {
    final uid = employeeUid.trim();
    if (uid.isEmpty) return;
    final existing = await _employerTrackedWorkspaces(
      employerUid,
    ).where('employeeUid', isEqualTo: uid).get();
    final desiredIds = desired.map((e) => e.accessId).toSet();
    for (final d in existing.docs) {
      if (!desiredIds.contains(d.id)) {
        await d.reference.delete();
      }
    }
    for (final a in desired) {
      final ref = _employerTrackedWorkspaces(employerUid).doc(a.accessId);
      final cur = await ref.get();
      if (cur.exists) {
        await ref.set(a.toMergePatch(), SetOptions(merge: true));
      } else {
        await ref.set(a.toWriteMap());
      }
    }
  }

  /// Recomputes `trackedWorkspaces` for every tracked employee row from live workspace data.
  ///
  /// Call explicitly from Settings — no automatic migration.
  Future<int> rebuildTrackedWorkspaceAccess({
    required String employerUid,
    required String employerEmail,
    bool preferServer = false,
  }) async {
    final employerDomain = emailDomain(employerEmail);
    if (employerDomain == null) {
      throw EmployerLinkException(
        'Employer email domain is required to rebuild workspace access.',
      );
    }
    final employerEmailLower = employerEmail.trim().toLowerCase();
    await ensureTrackedEmployeeUidAccessDocs(employerUid);
    final trackedSnap = await _employerTracked(employerUid).get();
    var written = 0;
    final byEmployee = <String, Set<TrackedWorkspaceAccess>>{};
    for (final d in trackedSnap.docs) {
      final data = d.data();
      final employeeUid = (data['employeeUid'] as String?)?.trim() ?? '';
      final emailLower =
          (data['employeeEmailLower'] as String?)?.trim().toLowerCase() ?? '';
      final companySlug =
          (data['companySlug'] as String?)?.trim().toLowerCase() ?? '';
      final companyName = (data['companyName'] as String?)?.trim() ?? '';
      if (employeeUid.isEmpty || emailLower.isEmpty || companySlug.isEmpty) {
        continue;
      }
      final workspaces = await fetchEmployeeWorkspaces(
        employeeUid,
        preferServer: preferServer,
      );
      for (final w in workspaces) {
        if ((w.companySlug ?? '').trim().toLowerCase() != companySlug) continue;
        if (!twp.workspaceQualifiesForEmployerPanel(
          w: w,
          employeeEmailLower: emailLower,
          employerDomain: employerDomain,
          normalizedCompanySlug: companySlug,
          employerEmailLower: employerEmailLower,
        )) {
          continue;
        }
        final id = TrackedWorkspaceAccess.docIdFor(employeeUid, w.id);
        byEmployee.putIfAbsent(employeeUid, () => <TrackedWorkspaceAccess>{});
        byEmployee[employeeUid]!.add(
          TrackedWorkspaceAccess(
            accessId: id,
            employeeUid: employeeUid,
            workspaceId: w.id,
            employeeEmailLower: emailLower,
            companyName: companyName.isNotEmpty
                ? companyName
                : (w.companyName ?? ''),
            companySlug: companySlug,
            workspaceName: w.name,
          ),
        );
        written++;
      }
    }
    for (final e in byEmployee.entries) {
      await _replaceTrackedWorkspacesForEmployee(employerUid, e.key, e.value);
    }
    for (final d in trackedSnap.docs) {
      final uid = (d.data()['employeeUid'] as String?)?.trim() ?? '';
      if (uid.isNotEmpty) {
        await _setTrackedEmployeeUidAccess(employerUid, uid);
      }
    }
    return written;
  }

  Future<void> _syncTrackedWorkspacesForEmployeeUid({
    required String employerUid,
    required String employeeUid,
    required String employerEmailLower,
    required String employerDomain,
  }) async {
    final uid = employeeUid.trim();
    if (uid.isEmpty) return;
    final remaining = await _employerTracked(
      employerUid,
    ).where('employeeUid', isEqualTo: uid).get();
    if (remaining.docs.isEmpty) {
      await _deleteAllTrackedWorkspacesForEmployee(employerUid, uid);
      await _employerTrackedEmployeeUids(employerUid).doc(uid).delete();
      return;
    }
    final workspaces = await fetchEmployeeWorkspaces(uid);
    final desired = <TrackedWorkspaceAccess>{};
    for (final d in remaining.docs) {
      final data = d.data();
      final emailLower =
          (data['employeeEmailLower'] as String?)?.trim().toLowerCase() ?? '';
      final companySlug =
          (data['companySlug'] as String?)?.trim().toLowerCase() ?? '';
      final companyName = (data['companyName'] as String?)?.trim() ?? '';
      if (emailLower.isEmpty || companySlug.isEmpty) continue;
      for (final w in workspaces) {
        if ((w.companySlug ?? '').trim().toLowerCase() != companySlug) continue;
        if (!twp.workspaceQualifiesForEmployerPanel(
          w: w,
          employeeEmailLower: emailLower,
          employerDomain: employerDomain,
          normalizedCompanySlug: companySlug,
          employerEmailLower: employerEmailLower,
        )) {
          continue;
        }
        final id = TrackedWorkspaceAccess.docIdFor(uid, w.id);
        desired.add(
          TrackedWorkspaceAccess(
            accessId: id,
            employeeUid: uid,
            workspaceId: w.id,
            employeeEmailLower: emailLower,
            companyName: companyName.isNotEmpty
                ? companyName
                : (w.companyName ?? ''),
            companySlug: companySlug,
            workspaceName: w.name,
          ),
        );
      }
    }
    await _replaceTrackedWorkspacesForEmployee(employerUid, uid, desired);
    await _setTrackedEmployeeUidAccess(employerUid, uid);
  }

  /// Workspaces the employer may see for [employeeUid] (from `trackedWorkspaces` + live docs).
  Future<List<Workspace>> fetchEmployeeWorkspacesForEmployer(
    String employerUid,
    String employeeUid, {
    bool preferServer = false,
  }) async {
    final access = await fetchTrackedWorkspaces(employerUid);
    final uid = employeeUid.trim();
    final mineByWs = <String, TrackedWorkspaceAccess>{};
    for (final a in access.where((x) => x.employeeUid == uid)) {
      final wid = a.workspaceId.trim();
      if (wid.isEmpty) continue;
      mineByWs.putIfAbsent(wid, () => a);
    }
    final opts = GetOptions(
      source: preferServer ? Source.server : Source.serverAndCache,
    );
    final out = <Workspace>[];
    for (final a in mineByWs.values) {
      try {
        final d = await _db
            .collection('users')
            .doc(uid)
            .collection('workspaces')
            .doc(a.workspaceId.trim())
            .get(opts);
        if (d.exists && d.data() != null) {
          out.add(Workspace.fromDoc(d.id, d.data()!));
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            '[EmployerFS/fetchWorkspace] employer=$employerUid employee=$uid '
            'workspaceId=${a.workspaceId} err=$e',
          );
          debugPrintStack(stackTrace: st, label: 'employer_fetch_workspace');
        }
      }
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

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

  /// Reads employee time entries in `[start, end]` by `start` (no employer filter).
  Future<List<WorkEntry>> fetchEntriesInRange(
    String employeeUid,
    ReportPeriod period, {
    bool preferServer = false,
  }) async {
    final startTs = Timestamp.fromDate(period.start);
    final endTs = Timestamp.fromDate(period.endInclusive);
    final ref = _db.collection('users').doc(employeeUid).collection('entries');
    final q = ref
        .where('start', isGreaterThanOrEqualTo: startTs)
        .where('start', isLessThanOrEqualTo: endTs);
    final opts = GetOptions(
      source: preferServer ? Source.server : Source.serverAndCache,
    );
    final snap = await q.get(opts);
    return snap.docs.map((d) => WorkEntry.fromDoc(d.id, d.data())).toList();
  }

  /// Entries in range limited to `trackedWorkspaces` for this employer.
  Future<List<WorkEntry>> fetchEntriesInRangeForEmployer(
    String employerUid,
    String employeeUid,
    ReportPeriod period, {
    bool preferServer = false,
  }) async {
    final allowed = await trackedWorkspaceIdsForEmployee(
      employerUid,
      employeeUid,
    );
    if (allowed.isEmpty) {
      if (kDebugMode) {
        _logEmployerEntriesDebug(
          'fetchEntries SKIP',
          employerUid: employerUid,
          employeeUid: employeeUid,
          workspaceIds: allowed,
          chunkCount: 0,
          extra: 'workspaceIds empty',
        );
      }
      return [];
    }
    final chunks = workspaceIdChunksForWhereIn(allowed);
    if (chunks.isEmpty) {
      if (kDebugMode) {
        debugPrint(
          '[EmployerFS/fetchEntries] unexpected empty chunks employer=$employerUid employee=$employeeUid',
        );
      }
      return [];
    }
    if (kDebugMode) {
      _logEmployerEntriesDebug(
        'fetchEntries',
        employerUid: employerUid,
        employeeUid: employeeUid,
        workspaceIds: allowed,
        chunkCount: chunks.length,
      );
    }
    final startTs = Timestamp.fromDate(period.start);
    final endTs = Timestamp.fromDate(period.endInclusive);
    final ref = _db.collection('users').doc(employeeUid).collection('entries');
    final opts = GetOptions(
      source: preferServer ? Source.server : Source.serverAndCache,
    );
    final merged = <WorkEntry>[];
    final seen = <String>{};
    for (var ci = 0; ci < chunks.length; ci++) {
      final chunk = chunks[ci];
      if (chunk.isEmpty) continue;
      try {
        final snap = await ref
            .where('workspaceId', whereIn: chunk)
            .where('start', isGreaterThanOrEqualTo: startTs)
            .where('start', isLessThanOrEqualTo: endTs)
            .get(opts);
        if (kDebugMode) {
          debugPrint(
            '[EmployerFS/fetchEntries] chunk ${ci + 1}/${chunks.length} '
            'whereInSize=${chunk.length} docs=${snap.docs.length}',
          );
        }
        for (final d in snap.docs) {
          if (seen.add(d.id)) {
            merged.add(WorkEntry.fromDoc(d.id, d.data()));
          }
        }
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint(
            '[EmployerFS/fetchEntries] chunk ${ci + 1} failed employer=$employerUid '
            'employee=$employeeUid err=$e',
          );
          debugPrintStack(
            stackTrace: st,
            label: 'employer_fetch_entries_chunk',
          );
        }
      }
    }
    merged.sort((a, b) => a.start.compareTo(b.start));
    return merged;
  }

  /// Live updates when any **tracked-workspace** entry in [period] changes.
  Stream<void> entriesMonthTouchSignalsForEmployer(
    String employerUid,
    String employeeUid,
    ReportPeriod period,
  ) {
    late final StreamController<void> controller;
    StreamSubscription<List<TrackedWorkspaceAccess>>? accessSub;
    final entrySubs =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    Set<String>? lastAttachedIds;
    var attachGen = 0;

    void tearEntrySubs() {
      for (final s in entrySubs) {
        s.cancel();
      }
      entrySubs.clear();
    }

    void attachForWorkspaces(Set<String> allowedRaw) {
      final allowed = normalizedWorkspaceIdSet(allowedRaw);
      if (setEquals(lastAttachedIds, allowed)) return;
      lastAttachedIds = Set<String>.from(allowed);
      tearEntrySubs();
      final gen = ++attachGen;
      final captured = allowed;
      Future.microtask(() {
        if (gen != attachGen || controller.isClosed) return;
        if (captured.isEmpty) return;
        final startTs = Timestamp.fromDate(period.start);
        final endTs = Timestamp.fromDate(period.endInclusive);
        final ref = _db
            .collection('users')
            .doc(employeeUid)
            .collection('entries');
        final chunks = workspaceIdChunksForWhereIn(captured);
        if (kDebugMode && chunks.isNotEmpty) {
          debugPrint(
            '[EmployerFS/touchSignals] employer=$employerUid employee=$employeeUid '
            'chunks=${chunks.length} firstChunk=${chunks.first.length}',
          );
        }
        for (var ci = 0; ci < chunks.length; ci++) {
          final chunk = chunks[ci];
          if (chunk.isEmpty) continue;
          final sub = ref
              .where('workspaceId', whereIn: chunk)
              .where('start', isGreaterThanOrEqualTo: startTs)
              .where('start', isLessThanOrEqualTo: endTs)
              .snapshots()
              .listen(
                (_) {
                  if (!controller.isClosed) controller.add(null);
                },
                onError: (Object e, StackTrace st) {
                  if (kDebugMode) {
                    debugPrint(
                      '[EmployerFS/touchSignals] stream err employer=$employerUid '
                      'employee=$employeeUid chunk=${ci + 1}/${chunks.length} $e',
                    );
                    debugPrintStack(
                      stackTrace: st,
                      label: 'employer_touch_signals_chunk',
                    );
                  }
                },
              );
          entrySubs.add(sub);
        }
      });
    }

    controller = StreamController<void>.broadcast(
      onListen: () {
        accessSub = trackedWorkspaceAccessStream(employerUid).listen(
          (accessList) {
            final allowed = accessList
                .where((a) => a.employeeUid == employeeUid.trim())
                .map((a) => a.workspaceId);
            attachForWorkspaces(normalizedWorkspaceIdSet(allowed));
          },
          onError: (Object e, StackTrace st) {
            if (kDebugMode) {
              debugPrint(
                '[EmployerFS/touchSignals] accessStream err employer=$employerUid $e',
              );
              debugPrintStack(
                stackTrace: st,
                label: 'employer_touch_signals_access',
              );
            }
          },
        );
      },
      onCancel: () {
        attachGen++;
        tearEntrySubs();
        accessSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Unfiltered month query (employee-owned reads / tests).
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

  CollectionReference<Map<String, dynamic>> _employeeEntries(
    String employeeUid,
  ) => _db.collection('users').doc(employeeUid).collection('entries');

  /// Timesheet stream — only entries in [trackedWorkspaces] for this employer.
  Stream<List<WorkEntry>> employeeEntriesForMonthStream(
    String employerUid,
    String employeeUid,
    ReportPeriod period,
  ) {
    late final StreamController<List<WorkEntry>> controller;
    StreamSubscription<List<TrackedWorkspaceAccess>>? accessSub;
    final entrySubs =
        <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    Set<String>? lastAttachedIds;
    var attachGen = 0;

    void tearEntrySubs() {
      for (final s in entrySubs) {
        s.cancel();
      }
      entrySubs.clear();
    }

    void attachForWorkspaces(Set<String> allowedRaw) {
      final allowed = normalizedWorkspaceIdSet(allowedRaw);
      if (setEquals(lastAttachedIds, allowed)) return;
      lastAttachedIds = Set<String>.from(allowed);
      tearEntrySubs();
      final gen = ++attachGen;
      final captured = allowed;
      Future.microtask(() {
        if (gen != attachGen || controller.isClosed) return;
        if (captured.isEmpty) {
          if (!controller.isClosed) controller.add([]);
          return;
        }
        final startTs = Timestamp.fromDate(period.start);
        final endTs = Timestamp.fromDate(period.endInclusive);
        final ref = _db
            .collection('users')
            .doc(employeeUid)
            .collection('entries');
        final chunks = workspaceIdChunksForWhereIn(captured);
        if (kDebugMode) {
          _logEmployerEntriesDebug(
            'entriesMonthStream attach',
            employerUid: employerUid,
            employeeUid: employeeUid,
            workspaceIds: captured,
            chunkCount: chunks.length,
          );
        }
        final lists = List<List<WorkEntry>>.generate(
          chunks.length,
          (_) => <WorkEntry>[],
        );
        void emit() {
          final merged = <WorkEntry>[for (final l in lists) ...l]
            ..sort((a, b) => a.start.compareTo(b.start));
          if (!controller.isClosed) controller.add(merged);
        }

        emit();
        for (var i = 0; i < chunks.length; i++) {
          final idx = i;
          final chunk = chunks[i];
          if (chunk.isEmpty) continue;
          final sub = ref
              .where('workspaceId', whereIn: chunk)
              .where('start', isGreaterThanOrEqualTo: startTs)
              .where('start', isLessThanOrEqualTo: endTs)
              .snapshots()
              .listen(
                (snap) {
                  lists[idx] = snap.docs
                      .map((d) => WorkEntry.fromDoc(d.id, d.data()))
                      .toList();
                  emit();
                },
                onError: (Object e, StackTrace st) {
                  if (kDebugMode) {
                    debugPrint(
                      '[EmployerFS/entriesMonthStream] err employer=$employerUid '
                      'employee=$employeeUid chunk=${idx + 1}/${chunks.length} $e',
                    );
                    debugPrintStack(
                      stackTrace: st,
                      label: 'employer_entries_month_chunk',
                    );
                  }
                  lists[idx] = [];
                  emit();
                },
              );
          entrySubs.add(sub);
        }
      });
    }

    controller = StreamController<List<WorkEntry>>.broadcast(
      onListen: () {
        accessSub = trackedWorkspaceAccessStream(employerUid).listen(
          (accessList) {
            final allowed = accessList
                .where((a) => a.employeeUid == employeeUid.trim())
                .map((a) => a.workspaceId);
            attachForWorkspaces(normalizedWorkspaceIdSet(allowed));
          },
          onError: (Object e, StackTrace st) {
            if (kDebugMode) {
              debugPrint(
                '[EmployerFS/entriesMonthStream] accessStream err '
                'employer=$employerUid $e',
              );
              debugPrintStack(
                stackTrace: st,
                label: 'employer_entries_month_access',
              );
            }
            if (!controller.isClosed) controller.add([]);
          },
        );
      },
      onCancel: () {
        attachGen++;
        tearEntrySubs();
        accessSub?.cancel();
      },
    );
    return controller.stream;
  }

  /// Alias for timesheet — entries whose `start` falls in [period].
  Future<List<WorkEntry>> fetchEmployeeEntriesForMonth(
    String employerUid,
    String employeeUid,
    ReportPeriod period, {
    bool preferServer = false,
  }) => fetchEntriesInRangeForEmployer(
    employerUid,
    employeeUid,
    period,
    preferServer: preferServer,
  );

  /// Creates a document under `users/{employeeUid}/entries`. Caller supplies a map that satisfies
  /// [firestore.rules] (e.g. `createdBy`, `createdVia: employer_panel`).
  Future<String> createEmployeeEntry({
    required String employerUid,
    required String employeeUid,
    required Map<String, dynamic> data,
  }) async {
    final ws = data['workspaceId'];
    if (ws is! String || ws.trim().isEmpty) {
      throw EmployerWorkspaceAccessException('workspaceId is required.');
    }
    if (!await employerCanAccessWorkspace(employerUid, employeeUid, ws)) {
      throw EmployerWorkspaceAccessException(
        'This workspace is not shared with your employer account.',
      );
    }
    await _setTrackedEmployeeUidAccess(employerUid, employeeUid);
    final doc = _employeeEntries(employeeUid).doc();
    await doc.set(data);
    return doc.id;
  }

  Future<void> updateEmployeeEntry({
    required String employeeUid,
    required String entryId,
    required Map<String, dynamic> data,
    String? employerUid,
  }) async {
    if (employerUid != null) {
      final cur = await _employeeEntries(employeeUid).doc(entryId).get();
      final curData = cur.data();
      final fromPatch = data['workspaceId'];
      final targetWs = fromPatch is String ? fromPatch.trim() : '';
      final effectiveWs = targetWs.isNotEmpty
          ? targetWs
          : ((curData?['workspaceId'] as String?)?.trim() ?? '');
      if (effectiveWs.isEmpty ||
          !await employerCanAccessWorkspace(
            employerUid,
            employeeUid,
            effectiveWs,
          )) {
        throw EmployerWorkspaceAccessException(
          'This workspace is not shared with your employer account.',
        );
      }
    }
    await _employeeEntries(employeeUid).doc(entryId).update(data);
  }

  Future<void> softDeleteEmployeeEntry({
    required String employerUid,
    required String employeeUid,
    required String entryId,
  }) async {
    final doc = await _employeeEntries(employeeUid).doc(entryId).get();
    final ws = (doc.data()?['workspaceId'] as String?)?.trim() ?? '';
    if (!await employerCanAccessWorkspace(employerUid, employeeUid, ws)) {
      throw EmployerWorkspaceAccessException(
        'Cannot delete an entry outside shared workspaces.',
      );
    }
    await updateEmployeeEntry(
      employeeUid: employeeUid,
      entryId: entryId,
      data: employerEntrySoftDeletePatch(employerUid),
      employerUid: employerUid,
    );
  }

  Future<void> restoreEmployeeEntry({
    required String employerUid,
    required String employeeUid,
    required String entryId,
  }) async {
    final doc = await _employeeEntries(employeeUid).doc(entryId).get();
    final ws = (doc.data()?['workspaceId'] as String?)?.trim() ?? '';
    if (!await employerCanAccessWorkspace(employerUid, employeeUid, ws)) {
      throw EmployerWorkspaceAccessException(
        'Cannot restore an entry outside shared workspaces.',
      );
    }
    await updateEmployeeEntry(
      employeeUid: employeeUid,
      entryId: entryId,
      data: employerEntryRestorePatch(employerUid),
      employerUid: employerUid,
    );
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
    String trackedId, {
    required String employerEmail,
  }) async {
    final employerDomain = emailDomain(employerEmail);
    final employerEmailLower = employerEmail.trim().toLowerCase();
    final ref = _employerTracked(employerUid).doc(trackedId);
    final snap = await ref.get();
    final removedUid = snap.data()?['employeeUid'] as String?;
    await ref.delete();
    if (removedUid != null && removedUid.trim().isNotEmpty) {
      if (employerDomain != null) {
        await _syncTrackedWorkspacesForEmployeeUid(
          employerUid: employerUid,
          employeeUid: removedUid.trim(),
          employerEmailLower: employerEmailLower,
          employerDomain: employerDomain,
        );
      } else {
        final others = await _employerTracked(
          employerUid,
        ).where('employeeUid', isEqualTo: removedUid).limit(1).get();
        if (others.docs.isEmpty) {
          await _deleteAllTrackedWorkspacesForEmployee(
            employerUid,
            removedUid.trim(),
          );
          await _employerTrackedEmployeeUids(
            employerUid,
          ).doc(removedUid.trim()).delete();
        }
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

  /// Last activity among entries the employer may see (`trackedWorkspaces`).
  Future<DateTime?> fetchLastActivityAtForEmployer(
    String employerUid,
    String employeeUid, {
    bool preferServer = false,
  }) async {
    final allowed = await trackedWorkspaceIdsForEmployee(
      employerUid,
      employeeUid,
    );
    if (allowed.isEmpty) return null;
    final opts = GetOptions(
      source: preferServer ? Source.server : Source.serverAndCache,
    );
    DateTime? best;
    final entriesCol = _db
        .collection('users')
        .doc(employeeUid)
        .collection('entries');
    for (final wid in allowed) {
      try {
        final snap = await entriesCol
            .where('workspaceId', isEqualTo: wid)
            .where('isDeleted', isEqualTo: false)
            .orderBy('updatedAt', descending: true)
            .limit(1)
            .get(opts);
        if (snap.docs.isEmpty) continue;
        final e = WorkEntry.fromDoc(snap.docs.first.id, snap.docs.first.data());
        final ts = e.updatedAt ?? e.start;
        if (best == null || ts.isAfter(best)) best = ts;
      } catch (_) {
        final snap = await entriesCol
            .where('workspaceId', isEqualTo: wid)
            .orderBy('start', descending: true)
            .limit(40)
            .get(opts);
        for (final d in snap.docs) {
          final e = WorkEntry.fromDoc(d.id, d.data());
          if (e.isDeleted) continue;
          final ts = e.updatedAt ?? e.start;
          if (best == null || ts.isAfter(best)) best = ts;
        }
      }
    }
    return best;
  }

  /// **MVP:** Employer may update billing fields on the employee workspace document.
  /// **TODO (mobile):** Firestore is source of truth; ensure the mobile client merges server writes
  /// instead of overwriting with stale local cache after employer edits.
  Future<void> updateWorkspaceBilling({
    required String employerUid,
    required String employeeUid,
    required String workspaceId,
    required double hourlyRate,
    required String currency,
  }) async {
    if (!await employerCanAccessWorkspace(
      employerUid,
      employeeUid,
      workspaceId,
    )) {
      throw EmployerWorkspaceAccessException(
        'This workspace is not shared with your employer account.',
      );
    }
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

  Future<void> _maybeRevokeTrackedEmployeeUidIfUnused(
    String employerUid,
    String employeeUid,
  ) async {
    final uid = employeeUid.trim();
    if (uid.isEmpty) return;
    final q = await _employerTracked(
      employerUid,
    ).where('employeeUid', isEqualTo: uid).limit(1).get();
    if (q.docs.isEmpty) {
      await _employerTrackedEmployeeUids(employerUid).doc(uid).delete();
    }
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

    final employerEmailLower = employerEmail.trim().toLowerCase();

    final index = await getUserEmailIndex(employeeEmailLower);
    if (index == null || index.uid.isEmpty) {
      throw EmployerLinkException('Employee not found');
    }

    final employeeUid = index.uid.trim();
    await _setTrackedEmployeeUidAccess(employerUid, employeeUid);

    try {
      final workspaces = await fetchEmployeeWorkspaces(employeeUid);

      final qualifyingForSlug = workspaces.where((w) {
        if ((w.companySlug ?? '').trim().toLowerCase() != normalizedSlug) {
          return false;
        }
        return twp.workspaceQualifiesForEmployerPanel(
          w: w,
          employeeEmailLower: employeeEmailLower,
          employerDomain: employerDomain,
          normalizedCompanySlug: normalizedSlug,
          employerEmailLower: employerEmailLower,
        );
      }).toList();

      if (qualifyingForSlug.isEmpty) {
        throw EmployerLinkException('No shared project found for this company');
      }

      final matched = qualifyingForSlug.first;
      final wsDomain = matched.employeeWorkEmailDomain?.trim().toLowerCase();
      if (wsDomain == null || wsDomain.isEmpty || wsDomain != employerDomain) {
        throw EmployerLinkException(
          'Employer email domain does not match employee work email domain',
        );
      }

      final existing = await _employerTracked(employerUid)
          .where('employeeUid', isEqualTo: employeeUid)
          .where('companySlug', isEqualTo: normalizedSlug)
          .limit(1)
          .get();

      if (existing.docs.isNotEmpty) {
        final doc = existing.docs.first;
        final patch = _personalEmployeePatchFromIndex(index, doc.data());
        if (patch.isNotEmpty) {
          await doc.reference.update(patch);
        }
        await _setTrackedEmployeeUidAccess(employerUid, employeeUid);
        await _syncTrackedWorkspacesForEmployeeUid(
          employerUid: employerUid,
          employeeUid: employeeUid,
          employerEmailLower: employerEmailLower,
          employerDomain: employerDomain,
        );
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
      await _setTrackedEmployeeUidAccess(employerUid, employeeUid);
      await _syncTrackedWorkspacesForEmployeeUid(
        employerUid: employerUid,
        employeeUid: employeeUid,
        employerEmailLower: employerEmailLower,
        employerDomain: employerDomain,
      );
    } catch (e) {
      final dup =
          e is EmployerLinkException &&
          e.message.contains('already on your list');
      if (!dup) {
        await _maybeRevokeTrackedEmployeeUidIfUnused(employerUid, employeeUid);
      }
      rethrow;
    }
  }
}

class EmployerWorkspaceAccessException implements Exception {
  EmployerWorkspaceAccessException(this.message);
  final String message;

  @override
  String toString() => message;
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
