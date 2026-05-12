import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:equatable/equatable.dart';

/// Document at `userEmailIndex/{emailLower}` — maps login email to Firebase Auth uid.
///
/// **TODO (mobile app):** After login / profile creation the mobile app should create or
/// update this document so the employer panel can resolve employee emails to UIDs.
/// If this collection is empty or stale, "Employee not found" will appear during linking.
class UserEmailIndex extends Equatable {
  const UserEmailIndex({
    required this.uid,
    required this.email,
    required this.emailLower,
    this.displayName,
    this.createdAt,
  });

  final String uid;
  final String email;
  final String emailLower;
  final String? displayName;
  final DateTime? createdAt;

  factory UserEmailIndex.fromDoc(String docId, Map<String, dynamic> data) {
    return UserEmailIndex(
      uid: data['uid'] as String? ?? '',
      email: data['email'] as String? ?? '',
      emailLower: data['emailLower'] as String? ?? docId,
      displayName: data['displayName'] as String?,
      createdAt: _ts(data['createdAt']),
    );
  }

  static DateTime? _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  @override
  List<Object?> get props => [uid, emailLower];
}
