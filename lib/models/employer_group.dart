import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:equatable/equatable.dart';

class EmployerGroup extends Equatable {
  const EmployerGroup({
    required this.id,
    required this.name,
    this.legacyColorHex,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// Optional legacy field from older panel writes; new groups omit it in Firestore.
  final String? legacyColorHex;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory EmployerGroup.fromDoc(String id, Map<String, dynamic> data) {
    final raw = data['colorHex'];
    String? legacy;
    if (raw is String && raw.trim().isNotEmpty) {
      legacy = raw.trim();
    }
    return EmployerGroup(
      id: id,
      name: data['name'] as String? ?? '',
      legacyColorHex: legacy,
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  @override
  List<Object?> get props => [id];
}
