import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class EmployerGroup extends Equatable {
  const EmployerGroup({
    required this.id,
    required this.name,
    required this.colorHex,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String colorHex;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory EmployerGroup.fromDoc(String id, Map<String, dynamic> data) {
    return EmployerGroup(
      id: id,
      name: data['name'] as String? ?? '',
      colorHex: data['colorHex'] as String? ?? '#64748B',
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  Map<String, dynamic> toWrite() => {
    'name': name,
    'colorHex': colorHex,
    'updatedAt': FieldValue.serverTimestamp(),
  };

  @override
  List<Object?> get props => [id];
}
