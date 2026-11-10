/// Application user (affected person or rescue operator).
///
/// Authentication in this version is local/demo only — no auth server is
/// required for the first runnable release.
library;

import '../core/utils/cast.dart';
import '../core/utils/time_format.dart';

enum UserRole {
  affected('AFFECTED', 'Affected User'),
  rescue('RESCUE', 'Rescue Team');

  const UserRole(this.code, this.label);

  final String code;
  final String label;

  static UserRole? fromCode(String? code) {
    if (code == null) return null;
    for (final r in UserRole.values) {
      if (r.code == code) return r;
    }
    return null;
  }
}

class AppUser {
  const AppUser({
    required this.userId,
    required this.displayName,
    required this.role,
    this.phone,
    this.teamId,
    this.createdAt,
  });

  final String userId;
  final String displayName;
  final UserRole role;
  final String? phone;
  final String? teamId;
  final DateTime? createdAt;

  bool get isRescue => role == UserRole.rescue;
  bool get isAffected => role == UserRole.affected;

  AppUser copyWith({String? displayName, String? teamId}) => AppUser(
        userId: userId,
        displayName: displayName ?? this.displayName,
        role: role,
        phone: phone,
        teamId: teamId ?? this.teamId,
        createdAt: createdAt,
      );

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'displayName': displayName,
        'role': role.code,
        if (phone != null) 'phone': phone,
        if (teamId != null) 'teamId': teamId,
        if (createdAt != null) 'createdAt': formatUtc(createdAt!),
      };

  static AppUser fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    return AppUser(
      userId: asString(m['userId'], fallback: 'USER-UNKNOWN'),
      displayName: asString(m['displayName'], fallback: 'User'),
      role: UserRole.fromCode(asString(m['role'])) ?? UserRole.affected,
      phone: asString(m['phone'], fallback: '') == ''
          ? null
          : asString(m['phone']),
      teamId: asString(m['teamId'], fallback: '') == ''
          ? null
          : asString(m['teamId']),
      createdAt: parseUtc(asString(m['createdAt'], fallback: '')),
    );
  }
}