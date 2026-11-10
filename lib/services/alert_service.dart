/// Alert derivation service.
///
/// WHY THIS EXISTS
/// ---------------
/// The alerts feed must never contain invented information. Every alert this
/// service writes is either
///
///  1. **derived** from a record that really exists on this device (an SOS that
///     changed status, a critical flood report, a shelter that filled up, an
///     urgent help request), or
///  2. an **advisory a rescue operator typed in on this device**.
///
/// Nothing is fetched, guessed or fabricated.
///
/// IDEMPOTENCE
/// -----------
/// [refresh] runs after every relevant local change. Each derived alert carries
/// a stable [AlertRecord.dedupeKey] built from the fact it reports, so running
/// [refresh] a hundred times produces exactly the same feed as running it once.
library;

import '../core/constants/app_constants.dart';
import '../core/utils/id_generator.dart';
import '../models/alert_record.dart';
import '../models/enums/alert_severity.dart';
import '../models/enums/flood_severity.dart';
import '../models/enums/help_category.dart';
import '../models/enums/shelter_status.dart';
import '../models/enums/sos_priority.dart';
import '../models/enums/sos_status.dart';
import '../models/flood_report.dart';
import '../models/help_request.dart';
import '../models/shelter.dart';
import '../models/sos_request.dart';
import '../repositories/alert_repository.dart';
import '../repositories/flood_report_repository.dart';
import '../repositories/help_request_repository.dart';
import '../repositories/shelter_repository.dart';
import '../repositories/sos_repository.dart';

/// Severity a derived SOS-status alert carries.
AlertSeverity sosStatusToSeverity(SosStatus status) => switch (status) {
      SosStatus.pending => AlertSeverity.info,
      SosStatus.acknowledged => AlertSeverity.info,
      SosStatus.rescueAssigned => AlertSeverity.warning,
      SosStatus.inProgress => AlertSeverity.warning,
      SosStatus.resolved => AlertSeverity.info,
    };

class AlertService {
  AlertService({
    required this.alertRepository,
    required this.sosRepository,
    required this.floodReportRepository,
    required this.helpRequestRepository,
    required this.shelterRepository,
    required this.idGenerator,
    DateTime Function()? now,
  }) : _now = now ?? _defaultNow;

  final AlertRepository alertRepository;
  final SosRepository sosRepository;
  final FloodReportRepository floodReportRepository;
  final HelpRequestRepository helpRequestRepository;
  final ShelterRepository shelterRepository;
  final IdGenerator idGenerator;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  // -------------------------------------------------------------------------
  // Derivation
  // -------------------------------------------------------------------------

  /// Recomputes the derived feed and writes only the alerts that are missing.
  ///
  /// Returns the number of newly created alerts.
  Future<int> refresh() async {
    final existing = await alertRepository.getAll();
    final known = existing.map((a) => a.dedupeKey).toSet();

    // Candidates are filtered against `known` as they are built, so a refresh
    // that runs twice over unchanged data writes nothing.
    final candidates = <AlertRecord>[
      ..._sosAlerts(await sosRepository.getAll(), known),
      ..._floodAlerts(await floodReportRepository.getAll(), known),
      ..._helpAlerts(await helpRequestRepository.getAll(), known),
      ..._shelterAlerts(await shelterRepository.getAll(), known),
    ];

    var created = 0;
    for (final alert in candidates) {
      await alertRepository.save(alert);
      known.add(alert.dedupeKey);
      created++;
    }
    await alertRepository.prune();
    return created;
  }

  /// One alert per SOS status the record actually reached, plus one extra for a
  /// critical SOS so it cannot be lost in a long list.
  List<AlertRecord> _sosAlerts(List<SosRequest> sosList, Set<String> known) {
    final out = <AlertRecord>[];
    void add(AlertRecord? alert) {
      if (alert != null) out.add(alert);
    }

    for (final sos in sosList) {
      if (sos.status != SosStatus.pending) {
        add(_alert(
          source: AlertSource.sos,
          topic: 'status-${sos.status.code}',
          relatedId: sos.sosId,
          severity: sosStatusToSeverity(sos.status),
          title: '${sos.sosId} · ${sos.status.label}',
          description: '${sos.emergencyType.label} for '
              '${sos.totalPeople} people is now ${sos.status.label.toLowerCase()}.',
          latitude: sos.latitude,
          longitude: sos.longitude,
          timestamp: _lastTransitionAt(sos),
          dedupeKeys: known,
        ));
      }
      if (sos.priority == SosPriority.critical && sos.status.isActive) {
        add(_alert(
          source: AlertSource.sos,
          topic: 'priority-critical',
          relatedId: sos.sosId,
          severity: AlertSeverity.critical,
          title: 'Critical SOS nearby · ${sos.sosId}',
          description:
              '${sos.totalPeople} people need rescue. ${sos.description}',
          latitude: sos.latitude,
          longitude: sos.longitude,
          timestamp: sos.timestamp,
          dedupeKeys: known,
        ));
      }
    }
    return out;
  }

  /// Alerts for flood conditions severe enough to matter: critical severity or
  /// waist-deep-and-above water.
  List<AlertRecord> _floodAlerts(
    List<FloodReport> reports,
    Set<String> known,
  ) {
    final cutoff = _now().toUtc().subtract(Limits.floodReportFreshness);
    final out = <AlertRecord>[];
    for (final report in reports) {
      if (report.timestamp.isBefore(cutoff)) continue;
      final deep = report.waterDepth.approximateMetres >=
          WaterDepthCategory.waistDeep.approximateMetres;
      if (report.severity != FloodSeverity.critical && !deep) continue;
      final alert = _alert(
        source: AlertSource.floodReport,
        topic: 'flood-${report.severity.code}',
        relatedId: report.reportId,
        severity: report.severity == FloodSeverity.critical
            ? AlertSeverity.critical
            : AlertSeverity.warning,
        title: '${report.severity.label} flooding reported',
        description: '${report.waterDepth.label} water. '
            '${report.affectedPeople} people affected. ${report.description}',
        latitude: report.latitude,
        longitude: report.longitude,
        timestamp: report.timestamp,
        dedupeKeys: known,
      );
      if (alert != null) out.add(alert);
    }
    return out;
  }

  /// Alerts for help requests a rescue operator should look at first.
  List<AlertRecord> _helpAlerts(
    List<HelpRequest> requests,
    Set<String> known,
  ) {
    final out = <AlertRecord>[];
    for (final request in requests) {
      if (!request.isOpen) continue;
      if (request.priority != HelpPriority.urgent) continue;
      final alert = _alert(
        source: AlertSource.helpRequest,
        topic: 'urgent',
        relatedId: request.requestId,
        severity: AlertSeverity.danger,
        title: 'Urgent ${request.category.label.toLowerCase()} request',
        description: '${request.peopleCount} people · ${request.description}',
        latitude: request.latitude,
        longitude: request.longitude,
        timestamp: request.statusUpdatedAt ?? request.timestamp,
        dedupeKeys: known,
      );
      if (alert != null) out.add(alert);
    }
    return out;
  }

  /// One alert per shelter that has no space left.
  List<AlertRecord> _shelterAlerts(
    List<Shelter> shelters,
    Set<String> known,
  ) {
    final out = <AlertRecord>[];
    for (final shelter in shelters) {
      if (shelter.status != ShelterStatus.full) continue;
      final alert = _alert(
        source: AlertSource.shelter,
        topic: 'full',
        relatedId: shelter.shelterId,
        severity: AlertSeverity.warning,
        title: '${shelter.name} is full',
        description: shelter.capacity <= 0
            ? 'This shelter is not accepting new arrivals right now.'
            : 'All ${shelter.capacity} places are taken.',
        locationLabel: shelter.name,
        latitude: shelter.latitude,
        longitude: shelter.longitude,
        timestamp: _now().toUtc(),
        dedupeKeys: known,
      );
      if (alert != null) out.add(alert);
    }
    return out;
  }

  /// Builds an alert, or null when its dedupe key is already known.
  AlertRecord? _alert({
    required AlertSource source,
    required String topic,
    required String? relatedId,
    required AlertSeverity severity,
    required String title,
    required String description,
    required double? latitude,
    required double? longitude,
    required DateTime timestamp,
    required Set<String> dedupeKeys,
    String? locationLabel,
  }) {
    final key =
        alertDedupeKey(source: source, topic: topic, relatedId: relatedId);
    if (dedupeKeys.contains(key)) return null;
    return AlertRecord(
      alertId: idGenerator.alertId(at: timestamp),
      title: title,
      description: description,
      severity: severity,
      source: source,
      timestamp: timestamp.toUtc(),
      dedupeKey: key,
      locationLabel: locationLabel,
      latitude: latitude,
      longitude: longitude,
      relatedId: relatedId,
    );
  }

  /// Timestamp of the newest status change, so an alert about a transition is
  /// ordered by when the transition happened rather than by the SOS timestamp.
  static DateTime _lastTransitionAt(SosRequest sos) {
    if (sos.statusHistory.isEmpty) return sos.timestamp;
    return sos.statusHistory.last.timestamp;
  }

  // -------------------------------------------------------------------------
  // Operator advisories
  // -------------------------------------------------------------------------

  /// Records an advisory typed by a rescue operator on this device.
  ///
  /// The dedupe key embeds the freshly minted id, so two advisories with the
  /// same wording are both kept (an operator repeating a warning intends it to
  /// appear again).
  Future<AlertRecord> publishAdvisory({
    required String title,
    required String description,
    required AlertSeverity severity,
    double? latitude,
    double? longitude,
    String? locationLabel,
  }) async {
    final at = _now().toUtc();
    final alertId = idGenerator.alertId(at: at);
    final alert = AlertRecord(
      alertId: alertId,
      title: title.trim(),
      description: description.trim(),
      severity: severity,
      source: AlertSource.system,
      timestamp: at,
      dedupeKey: alertDedupeKey(
        source: AlertSource.system,
        topic: 'advisory',
        relatedId: alertId,
      ),
      locationLabel: locationLabel,
      latitude: latitude,
      longitude: longitude,
    );
    await alertRepository.save(alert);
    return alert;
  }

  // -------------------------------------------------------------------------
  // Read state
  // -------------------------------------------------------------------------

  Future<void> markRead(String alertId) => alertRepository.markRead(alertId);

  Future<int> markAllRead() => alertRepository.markAllRead();

  Future<int> unreadCount() => alertRepository.unreadCount();

  /// Drops every alert whose dedupe key matches [dedupeKey] (used when the
  /// record an alert describes is deleted).
  Future<void> forget(String dedupeKey) async {
    final all = await alertRepository.getAll();
    for (final alert in all) {
      if (alert.dedupeKey == dedupeKey) {
        await alertRepository.delete(alert.alertId);
      }
    }
  }
}
