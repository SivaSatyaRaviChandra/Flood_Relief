/// A flood incident reported from the field.
///
/// Reports are stored locally first (offline-first) and queued for relay. They
/// are distinct from an SOS: a *report* describes the state of the water, an
/// SOS describes people who need rescue.
library;

import '../core/utils/cast.dart';
import '../core/utils/time_format.dart';
import 'enums/flood_severity.dart';

class FloodReport {
  const FloodReport({
    required this.reportId,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.severity,
    required this.waterDepth,
    required this.affectedPeople,
    required this.description,
    this.accuracy,
    this.reporterId,
    this.reporterName,
    this.photoPath,
    this.verified = false,
  });

  final String reportId;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? accuracy;

  final FloodSeverity severity;
  final WaterDepthCategory waterDepth;
  final int affectedPeople;
  final String description;

  final String? reporterId;
  final String? reporterName;

  /// Local filesystem path of an attached photo, when the user added one.
  /// Images are never uploaded by this build; the path is kept so the report
  /// stays self-describing on the device.
  final String? photoPath;

  /// True once a rescue operator has confirmed the report.
  final bool verified;

  bool get hasPhoto => photoPath != null && photoPath!.isNotEmpty;

  FloodReport copyWith({
    FloodSeverity? severity,
    WaterDepthCategory? waterDepth,
    int? affectedPeople,
    String? description,
    bool? verified,
    String? photoPath,
    bool clearPhoto = false,
  }) {
    return FloodReport(
      reportId: reportId,
      timestamp: timestamp,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      severity: severity ?? this.severity,
      waterDepth: waterDepth ?? this.waterDepth,
      affectedPeople: affectedPeople ?? this.affectedPeople,
      description: description ?? this.description,
      reporterId: reporterId,
      reporterName: reporterName,
      photoPath: clearPhoto ? null : (photoPath ?? this.photoPath),
      verified: verified ?? this.verified,
    );
  }

  Map<String, dynamic> toMap() => {
        'reportId': reportId,
        'timestamp': formatUtc(timestamp),
        'latitude': latitude,
        'longitude': longitude,
        if (accuracy != null) 'accuracy': accuracy,
        'severity': severity.code,
        'waterDepth': waterDepth.code,
        'affectedPeople': affectedPeople,
        'description': description,
        if (reporterId != null) 'reporterId': reporterId,
        if (reporterName != null) 'reporterName': reporterName,
        if (photoPath != null) 'photoPath': photoPath,
        'verified': verified,
      };

  static FloodReport fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    return FloodReport(
      reportId: asString(m['reportId']),
      timestamp:
          parseUtc(asString(m['timestamp'])) ?? DateTime.now().toUtc(),
      latitude: asDouble(m['latitude']) ?? 0,
      longitude: asDouble(m['longitude']) ?? 0,
      accuracy: asDouble(m['accuracy']),
      severity: FloodSeverity.fromCode(asString(m['severity'])) ??
          FloodSeverity.low,
      waterDepth: WaterDepthCategory.fromCode(asString(m['waterDepth'])) ??
          WaterDepthCategory.ankleDeep,
      affectedPeople: asInt(m['affectedPeople']) ?? 0,
      description: asString(m['description']),
      reporterId: _emptyToNull(m['reporterId']),
      reporterName: _emptyToNull(m['reporterName']),
      photoPath: _emptyToNull(m['photoPath']),
      verified: asBool(m['verified']),
    );
  }

  static String? _emptyToNull(dynamic value) {
    final text = asString(value);
    return text.isEmpty ? null : text;
  }
}
