import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class WorkEntry extends Equatable {
  const WorkEntry({
    required this.id,
    required this.workspaceId,
    required this.start,
    this.end,
    this.mode = '',
    this.updatedAt,
    this.isDeleted = false,
    this.taskTitle,
    this.note,
    this.isBillable,
    this.entryType,
  });

  final String id;
  final String workspaceId;
  final DateTime start;
  final DateTime? end;
  final String mode;
  final DateTime? updatedAt;
  final bool isDeleted;
  final String? taskTitle;
  final String? note;
  final bool? isBillable;

  /// work, vacation, sickLeave, businessTrip, other — matches mobile app assumption.
  final String? entryType;

  factory WorkEntry.fromDoc(String id, Map<String, dynamic> data) {
    return WorkEntry(
      id: id,
      workspaceId: data['workspaceId'] as String? ?? '',
      start: _reqTs(data['start']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      end: _ts(data['end']),
      mode: data['mode'] as String? ?? '',
      updatedAt: _ts(data['updatedAt']),
      isDeleted: data['isDeleted'] as bool? ?? false,
      taskTitle: data['taskTitle'] as String?,
      note: data['note'] as String?,
      isBillable: data['isBillable'] as bool?,
      entryType: data['entryType'] as String?,
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  static DateTime? _reqTs(dynamic v) => _ts(v);

  bool get isWorkEntry {
    final t = entryType;
    return t == null || t == 'work';
  }

  bool get effectiveBillable => isBillable ?? true;

  /// Duration for reporting; null if open entry.
  Duration? get duration {
    final e = end;
    if (e == null) return null;
    return e.difference(start);
  }

  @override
  List<Object?> get props => [id];
}
