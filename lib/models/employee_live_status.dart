import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Document at `users/{employeeUid}/live/status` — presence and timer (mobile-maintained).
class EmployeeLiveStatus extends Equatable {
  const EmployeeLiveStatus({
    this.isOnline,
    this.timerState,
    this.activeWorkspaceId,
    this.activeCompanySlug,
    this.activeWorkspaceName,
    this.lastSeenAt,
    this.updatedAt,
    this.accumulatedSecondsBeforePause,
    this.sessionStartedAt,
    this.billingRatePercent,
    this.hourlyRate,
    this.currency,
  });

  final bool? isOnline;
  /// `idle`, `running`, `paused` (case-insensitive when read).
  final String? timerState;
  final String? activeWorkspaceId;
  final String? activeCompanySlug;
  final String? activeWorkspaceName;
  final DateTime? lastSeenAt;
  final DateTime? updatedAt;
  final int? accumulatedSecondsBeforePause;
  final DateTime? sessionStartedAt;
  /// 0–100; defaults to 100 in UI if null.
  final double? billingRatePercent;
  /// Optional rate on live doc; falls back to workspace when null.
  final double? hourlyRate;
  /// Optional ISO currency from live doc.
  final String? currency;

  String get timerStateLower => (timerState ?? 'idle').trim().toLowerCase();

  /// Running: base + elapsed since [sessionStartedAt]. Paused/other: base only.
  int currentAccumulatedSeconds(DateTime at) {
    final base = accumulatedSecondsBeforePause ?? 0;
    if (timerStateLower != 'running') return base;
    final start = sessionStartedAt;
    if (start == null) return base;
    final delta = at.difference(start).inSeconds;
    return base + (delta > 0 ? delta : 0);
  }

  factory EmployeeLiveStatus.fromMap(Map<String, dynamic> data) {
    return EmployeeLiveStatus(
      isOnline: _bool(data['isOnline']),
      timerState: _str(data['timerState']),
      activeWorkspaceId: _str(data['activeWorkspaceId']),
      activeCompanySlug: _str(data['activeCompanySlug']),
      activeWorkspaceName: _str(data['activeWorkspaceName']),
      lastSeenAt: _ts(data['lastSeenAt']),
      updatedAt: _ts(data['updatedAt']),
      accumulatedSecondsBeforePause: _int(data['accumulatedSecondsBeforePause']),
      sessionStartedAt: _ts(data['sessionStartedAt']),
      billingRatePercent: _double(data['billingRatePercent']),
      hourlyRate: _double(data['hourlyRate']),
      currency: _str(data['currency']),
    );
  }

  static String? _str(dynamic v) {
    if (v == null) return null;
    if (v is String) {
      final t = v.trim();
      return t.isEmpty ? null : t;
    }
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  static bool? _bool(dynamic v) {
    if (v == null) return null;
    if (v is bool) return v;
    if (v is num) return v != 0;
    if (v is String) {
      final l = v.trim().toLowerCase();
      if (l == 'true' || l == '1') return true;
      if (l == 'false' || l == '0') return false;
    }
    return null;
  }

  static int? _int(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.round();
    if (v is String) return int.tryParse(v.trim());
    return null;
  }

  static double? _double(dynamic v) {
    if (v == null) return null;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v.trim());
    return null;
  }

  static DateTime? _ts(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate();
    if (v is DateTime) return v;
    if (v is int) {
      if (v > 2000000000000) return DateTime.fromMillisecondsSinceEpoch(v, isUtc: true).toLocal();
      if (v > 1000000000) return DateTime.fromMillisecondsSinceEpoch(v * 1000, isUtc: true).toLocal();
      return null;
    }
    if (v is num) {
      final i = v.round();
      if (i > 2000000000000) return DateTime.fromMillisecondsSinceEpoch(i, isUtc: true).toLocal();
      if (i > 1000000000) return DateTime.fromMillisecondsSinceEpoch(i * 1000, isUtc: true).toLocal();
    }
    return null;
  }

  @override
  List<Object?> get props => [updatedAt, timerState, isOnline, accumulatedSecondsBeforePause, sessionStartedAt];
}
