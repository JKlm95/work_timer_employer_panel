import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Document at `userEmailIndex/{emailLower}` — maps work email to Firebase Auth uid and profile fields.
///
/// **TODO (mobile app):** Keep this document updated after login / profile edits so the employer panel
/// can resolve emails and show names. If missing, linking and name sync will be limited.
class UserEmailIndex extends Equatable {
  const UserEmailIndex({
    required this.uid,
    required this.email,
    required this.emailLower,
    this.firstName,
    this.lastName,
    this.displayName,
    this.createdAt,
    this.updatedAt,
    this.providerIds,
  });

  final String uid;
  final String email;
  final String emailLower;
  final String? firstName;
  final String? lastName;
  final String? displayName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<String>? providerIds;

  factory UserEmailIndex.fromDoc(String docId, Map<String, dynamic> data) {
    final providers = data['providerIds'];
    return UserEmailIndex(
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      emailLower: data['emailLower'] as String? ?? docId,
      firstName: data['firstName'] as String?,
      lastName: data['lastName'] as String?,
      displayName: data['displayName'] as String?,
      createdAt: _ts(data['createdAt']),
      updatedAt: _ts(data['updatedAt']),
      providerIds: providers is List
          ? providers.map((e) => e.toString()).toList()
          : null,
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  @override
  List<Object?> get props => [uid, emailLower];
}
