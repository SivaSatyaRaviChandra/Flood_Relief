/// A request for assistance filed by a person in need.
///
/// Requests are saved locally before anything else happens, so filing one never
/// depends on connectivity. Sync is handled by the offline outbox; the status
/// shown to the user always reflects what is actually known.
library;

import '../core/utils/cast.dart';
import '../core/utils/time_format.dart';
import 'enums/help_category.dart';

class HelpRequest {
  const HelpRequest({
    required this.requestId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.category,
    required this.priority,
    required this.peopleCount,
    required this.description,
    required this.status,
    this.accuracy,
    this.reporterId,
    this.reporterName,
    this.assignedTeamId,
    this.statusUpdatedAt,
  });

  final String requestId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? accuracy;

  final HelpCategory category;
  final HelpPriority priority;
  final int peopleCount;
  final String description;
  final HelpRequestStatus status;

  final String? reporterId;
  final String? reporterName;
  final String? assignedTeamId;
  final DateTime? statusUpdatedAt;

  bool get isOpen => status.isOpen;

  HelpRequest copyWith({
    HelpRequestStatus? status,
    String? assignedTeamId,
    bool clearAssignedTeam = false,
    DateTime? statusUpdatedAt,
  }) {
    return HelpRequest(
      requestId: requestId,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      category: category,
      priority: priority,
      peopleCount: peopleCount,
      description: description,
      status: status ?? this.status,
      reporterId: reporterId,
      reporterName: reporterName,
      assignedTeamId:
          clearAssignedTeam ? null : (assignedTeamId ?? this.assignedTeamId),
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'requestId': requestId,
        'timestamp': formatUtc(timestamp),
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'category': category.code,
        'priority': priority.code,
        'peopleCount': peopleCount,
        'description': description,
        'status': status.code,
        if (reporterId != null) 'reporterId': reporterId,
        if (reporterName != null) 'reporterName': reporterName,
        if (assignedTeamId != null) 'assignedTeamId': assignedTeamId,
        if (statusUpdatedAt != null) 'statusUpdatedAt': formatUtc(statusUpdatedAt!),
      };

  static HelpRequest fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    return HelpRequest(
      requestId: asString(m['requestId']),
      timestamp:
          parseUtc(asString(m['timestamp'])) ?? DateTime.now().toUtc(),
      latitude: asDouble(m['latitude']) ?? 0,
      longitude: asDouble(m['longitude']) ?? 0,
      accuracy: asDouble(m['accuracy']),
      category: HelpCategory.fromCode(asString(m['category'])) ??
          HelpCategory.other,
      priority: HelpPriority.fromCode(asString(m['priority'])) ??
          HelpPriority.medium,
      peopleCount: asInt(m['peopleCount']) ?? 1,
      description: asString(m['description']),
      status: HelpRequestStatus.fromCode(asString(m['status'])) ??
          HelpRequestStatus.pending,
      reporterId: _emptyToNull(m['reporterId']),
      reporterName: _emptyToNull(m['reporterName']),
      assignedTeamId: _emptyToNull(m['assignedTeamId']),
      statusUpdatedAt: parseUtc(asString(m['statusUpdatedAt'], fallback: '')),
    );
  }

  static String? _emptyToNull(dynamic value) {
    final text = asString(value);
    return text.isEmpty ? null : text;
  }
}
