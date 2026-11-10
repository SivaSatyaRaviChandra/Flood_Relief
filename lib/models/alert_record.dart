/// A single alert shown in the Alerts feed.
///
/// Alerts are never invented: they are *derived* from data that really exists
/// on this device (an SOS that changed status, a critical flood report, a
/// shelter that filled up) or written locally by a rescue operator. See
/// `services/alert_service.dart` for the derivation rules.
library;

import '../core/utils/cast.dart';
import '../core/utils/time_format.dart';
import 'enums/alert_severity.dart';

/// What produced the alert. Used for grouping and for the detail subtitle.
enum AlertSource {
  sos('SOS', 'SOS update'),
  floodReport('FLOOD_REPORT', 'Flood report'),
  helpRequest('HELP_REQUEST', 'Help request'),
  shelter('SHELTER', 'Shelter update'),
  system('SYSTEM', 'Advisory');

  const AlertSource(this.code, this.label);

  final String code;
  final String label;

  static AlertSource? fromCode(String? code) {
    if (code == null) return null;
    for (final s in AlertSource.values) {
      if (s.code == code) return s;
    }
    return null;
  }
}

class AlertRecord {
  const AlertRecord({
    required this.alertId,
    required this.title,
    required this.description,
    required this.severity,
    required this.source,
    required this.timestamp,
    required this.dedupeKey,
    this.locationLabel,
    this.latitude,
    this.longitude,
    this.read = false,
    this.relatedId,
  });

  final String alertId;
  final String title;
  final String description;
  final AlertSeverity severity;
  final AlertSource source;
  final DateTime timestamp;

  /// Stable identity of *the fact* this alert reports ("sos/acknowledged/
  /// SOS-2026...", "floodReport/critical/FLD-...").
  ///
  /// Alerts are re-derived from local data on every change, so the feed must
  /// be idempotent: an alert whose [dedupeKey] already exists is never written
  /// twice.
  final String dedupeKey;

  /// Human readable place, e.g. "North Ward" or a shelter name.
  final String? locationLabel;

  final double? latitude;
  final double? longitude;

  /// The SOS / report / request this alert was derived from.
  final String? relatedId;

  final bool read;

  bool get hasCoordinates => latitude != null && longitude != null;

  AlertRecord copyWith({bool? read}) => AlertRecord(
        alertId: alertId,
        title: title,
        description: description,
        severity: severity,
        source: source,
        timestamp: timestamp,
        dedupeKey: dedupeKey,
        locationLabel: locationLabel,
        latitude: latitude,
        longitude: longitude,
        relatedId: relatedId,
        read: read ?? this.read,
      );

  Map<String, dynamic> toMap() => {
        'alertId': alertId,
        'title': title,
        'description': description,
        'severity': severity.code,
        'source': source.code,
        'timestamp': formatUtc(timestamp),
        'dedupeKey': dedupeKey,
        if (locationLabel != null) 'locationLabel': locationLabel,
        if (latitude != null) 'latitude': latitude,
        if (longitude != null) 'longitude': longitude,
        if (relatedId != null) 'relatedId': relatedId,
        'read': read,
      };

  static AlertRecord fromMap(dynamic map) {
    final m = map is Map ? Map<String, dynamic>.from(map) : const <String, dynamic>{};
    return AlertRecord(
      alertId: asString(m['alertId']),
      title: asString(m['title'], fallback: 'Alert'),
      description: asString(m['description']),
      severity: AlertSeverity.fromCode(asString(m['severity'])) ??
          AlertSeverity.info,
      source: AlertSource.fromCode(asString(m['source'])) ?? AlertSource.system,
      timestamp:
          parseUtc(asString(m['timestamp'])) ?? DateTime.now().toUtc(),
      dedupeKey: asString(m['dedupeKey'], fallback: asString(m['alertId'])),
      locationLabel:
          asString(m['locationLabel'], fallback: '') == ''
              ? null
              : asString(m['locationLabel']),
      latitude: asDouble(m['latitude']),
      longitude: asDouble(m['longitude']),
      relatedId: asString(m['relatedId'], fallback: '') == ''
          ? null
          : asString(m['relatedId']),
      read: asBool(m['read']),
    );
  }
}
