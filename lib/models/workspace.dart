import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

class Workspace extends Equatable {
  const Workspace({
    required this.id,
    required this.name,
    this.companyName,
    this.companySlug,
    this.employeeWorkEmail,
    this.employeeWorkEmailDomain,
    this.hourlyRate,
    this.currency,
    this.colorHex,
    this.isArchived = false,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? companyName;
  final String? companySlug;
  final String? employeeWorkEmail;
  final String? employeeWorkEmailDomain;
  final double? hourlyRate;
  final String? currency;
  final String? colorHex;
  final bool isArchived;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  factory Workspace.fromDoc(String id, Map<String, dynamic> data) {
    return Workspace(
      id: id,
      name: data['name'] as String? ?? '',
      companyName: data['companyName'] as String?,
      companySlug: data['companySlug'] as String?,
      employeeWorkEmail: data['employeeWorkEmail'] as String?,
      employeeWorkEmailDomain: data['employeeWorkEmailDomain'] as String?,
      hourlyRate: (data['hourlyRate'] as num?)?.toDouble(),
      currency: data['currency'] as String?,
      colorHex: data['colorHex'] as String?,
      isArchived: data['isArchived'] as bool? ?? false,
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
