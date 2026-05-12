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
      isOnline: data['isOnline'] as bool?,
      timerState: data['timerState'] as String?,
      activeWorkspaceId: data['activeWorkspaceId'] as String?,
      activeCompanySlug: data['activeCompanySlug'] as String?,
      activeWorkspaceName: data['activeWorkspaceName'] as String?,
      lastSeenAt: _ts(data['lastSeenAt']),
      updatedAt: _ts(data['updatedAt']),
      accumulatedSecondsBeforePause: (data['accumulatedSecondsBeforePause'] as num?)?.round(),
      sessionStartedAt: _ts(data['sessionStartedAt']),
      billingRatePercent: (data['billingRatePercent'] as num?)?.toDouble(),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  @override
  List<Object?> get props => [updatedAt, timerState, isOnline, accumulatedSecondsBeforePause, sessionStartedAt];
}
