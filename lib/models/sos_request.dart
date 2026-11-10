/// The immutable SOS request record.
///
/// This is the canonical local representation of an emergency. It is
/// serialized to a map for Hive and, for backend-ready REST endpoints, to a
/// matching JSON shape (see `remote/remote_sync.dart`).
library;

import 'dart:convert';

import '../core/utils/cast.dart';
import '../core/utils/time_format.dart';
import 'enums/emergency_type.dart';
import 'enums/sos_priority.dart';
import 'enums/sos_status.dart';
import 'people_info.dart';
import 'status_history.dart';

class SosRequest {
  const SosRequest({
    required this.sosId,
    required this.userId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.people,
    required this.emergencyType,
    required this.description,
    required this.priority,
    required this.status,
    this.assignedTeamId,
    required this.originDeviceId,
    this.hopCount = 0,
    this.acknowledged = false,
    this.acknowledgedAt,
    this.statusHistory = const [],
  });

  final String sosId;
  final String userId;
  final DateTime timestamp;

  final double latitude;
  final double longitude;
  final double? accuracy;

  final PeopleInfo people;
  final EmergencyType emergencyType;
  final String description;

  final SosPriority priority;
  final SosStatus status;

  final String? assignedTeamId;

  final String originDeviceId;
  final int hopCount;

  final bool acknowledged;
  final DateTime? acknowledgedAt;

  final List<StatusHistoryEntry> statusHistory;

  int get totalPeople => people.totalPeople;
  String get statusLabel => status.label;
  String get priorityLabel => priority.label;

  SosRequest copyWith({
    String? sosId,
    String? userId,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    double? accuracy,
    bool clearAccuracy = false,
    PeopleInfo? people,
    EmergencyType? emergencyType,
    String? description,
    SosPriority? priority,
    SosStatus? status,
    String? assignedTeamId,
    bool clearAssignedTeam = false,
    String? originDeviceId,
    int? hopCount,
    bool? acknowledged,
    DateTime? acknowledgedAt,
    bool clearAcknowledgedAt = false,
    List<StatusHistoryEntry>? statusHistory,
  }) {
    return SosRequest(
      sosId: sosId ?? this.sosId,
      userId: userId ?? this.userId,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      accuracy: clearAccuracy ? null : (accuracy ?? this.accuracy),
      people: people ?? this.people,
      emergencyType: emergencyType ?? this.emergencyType,
      description: description ?? this.description,
      priority: priority ?? this.priority,
      status: status ?? this.status,
      assignedTeamId:
          clearAssignedTeam ? null : (assignedTeamId ?? this.assignedTeamId),
      originDeviceId: originDeviceId ?? this.originDeviceId,
      hopCount: hopCount ?? this.hopCount,
      acknowledged: acknowledged ?? this.acknowledged,
      acknowledgedAt: clearAcknowledgedAt
          ? null
          : (acknowledgedAt ?? this.acknowledgedAt),
      statusHistory: statusHistory ?? this.statusHistory,
    );
  }

  Map<String, dynamic> toMap() => {
        'sosId': sosId,
        'userId': userId,
        'timestamp': formatUtc(timestamp),
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'totalPeople': people.totalPeople,
        'childrenCount': people.childrenCount,
        'elderlyCount': people.elderlyCount,
        'pregnantWomenCount': people.pregnantWomenCount,
        'specialAssistanceCount': people.specialAssistanceCount,
        'emergencyType': emergencyType.code,
        'description': description,
        'priority': priority.code,
        'status': status.code,
        if (assignedTeamId != null) 'assignedTeamId': assignedTeamId,
        'originDeviceId': originDeviceId,
        'hopCount': hopCount,
        'acknowledged': acknowledged,
        if (acknowledgedAt != null) 'acknowledgedAt': formatUtc(acknowledgedAt!),
        'statusHistory': statusHistory.map((e) => e.toMap()).toList(),
      };

  static SosRequest fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    final history = <StatusHistoryEntry>[];
    final rawHistory = m['statusHistory'];
    if (rawHistory is List) {
      for (final entry in rawHistory) {
        history.add(StatusHistoryEntry.fromMap(entry));
      }
    }
    return SosRequest(
      sosId: asString(m['sosId']),
      userId: asString(m['userId']),
      timestamp: parseUtc(asString(m['timestamp'])) ?? DateTime.now().toUtc(),
      latitude: asDouble(m['latitude']) ?? 0,
      longitude: asDouble(m['longitude']) ?? 0,
      accuracy: asDouble(m['accuracy']),
      people: PeopleInfo(
        totalPeople: asInt(m['totalPeople']) ?? 0,
        childrenCount: asInt(m['childrenCount']) ?? 0,
        elderlyCount: asInt(m['elderlyCount']) ?? 0,
        pregnantWomenCount: asInt(m['pregnantWomenCount']) ?? 0,
        specialAssistanceCount: asInt(m['specialAssistanceCount']) ?? 0,
      ),
      emergencyType: EmergencyType.fromCode(asString(m['emergencyType'])) ??
          EmergencyType.other,
      description: asString(m['description']),
      priority: SosPriority.fromCode(asString(m['priority'])) ?? SosPriority.low,
      status: SosStatus.fromCode(asString(m['status'])) ?? SosStatus.pending,
      assignedTeamId: asString(m['assignedTeamId'], fallback: '') == ''
          ? null
          : asString(m['assignedTeamId']),
      originDeviceId: asString(m['originDeviceId'], fallback: 'DEVICE-UNKNOWN'),
      hopCount: asInt(m['hopCount']) ?? 0,
      acknowledged: asBool(m['acknowledged']),
      acknowledgedAt: parseUtc(asString(m['acknowledgedAt'], fallback: '')),
      statusHistory: history,
    );
  }

  /// Serialize to a REST/JSON payload. Field names are identical to the
  /// PostgreSQL-compatible schema documented in the README.
  Map<String, dynamic> toJson() => {
        'sos_id': sosId,
        'user_id': userId,
        'timestamp': timestamp.toUtc().toIso8601String(),
        'latitude': latitude,
        'longitude': longitude,
        'accuracy': accuracy,
        'total_people': people.totalPeople,
        'children_count': people.childrenCount,
        'elderly_count': people.elderlyCount,
        'pregnant_women_count': people.pregnantWomenCount,
        'special_assistance_count': people.specialAssistanceCount,
        'emergency_type': emergencyType.code,
        'description': description,
        'priority': priority.code,
        'status': status.code,
        'assigned_team_id': assignedTeamId,
        'origin_device_id': originDeviceId,
        'hop_count': hopCount,
        'acknowledged': acknowledged,
        'acknowledged_at':
            acknowledgedAt?.toUtc().toIso8601String(),
      };

  String toJsonString() => jsonEncode(toJson());
}