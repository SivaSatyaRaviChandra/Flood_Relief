/// Rescue team entity.
library;

import '../core/utils/cast.dart';
import 'enums/team_status.dart';

class RescueTeam {
  const RescueTeam({
    required this.teamId,
    required this.teamName,
    required this.teamLeader,
    required this.contact,
    required this.status,
    this.latitude,
    this.longitude,
    this.baseLocation,
  });

  final String teamId;
  final String teamName;
  final String teamLeader;
  final String contact;
  final TeamStatus status;
  final double? latitude;
  final double? longitude;
  final String? baseLocation;

  RescueTeam copyWith({
    String? teamId,
    String? teamName,
    String? teamLeader,
    String? contact,
    TeamStatus? status,
    double? latitude,
    double? longitude,
    String? baseLocation,
  }) =>
      RescueTeam(
        teamId: teamId ?? this.teamId,
        teamName: teamName ?? this.teamName,
        teamLeader: teamLeader ?? this.teamLeader,
        contact: contact ?? this.contact,
        status: status ?? this.status,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
        baseLocation: baseLocation ?? this.baseLocation,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is RescueTeam && other.teamId == teamId;

  @override
  int get hashCode => teamId.hashCode;

  Map<String, dynamic> toMap() => {
        'teamId': teamId,
        'teamName': teamName,
        'teamLeader': teamLeader,
        'contact': contact,
        'status': status.code,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (baseLocation != null) 'baseLocation': baseLocation,
      };

  static RescueTeam fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    return RescueTeam(
      teamId: asString(m['teamId']),
      teamName: asString(m['teamName']),
      teamLeader: asString(m['teamLeader']),
      contact: asString(m['contact']),
      status: TeamStatus.fromCode(asString(m['status'])) ?? TeamStatus.available,
      latitude: asDouble(m['latitude']),
      longitude: asDouble(m['longitude']),
      baseLocation: asString(m['baseLocation'], fallback: '') == ''
          ? null
          : asString(m['baseLocation']),
    );
  }

  @override
  String toString() => 'RescueTeam($teamId, $teamName)';
}