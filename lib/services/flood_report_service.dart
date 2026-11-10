/// Flood report application service.
///
/// Business rules for field flood reports: validation, id generation, local
/// persistence (always before anything else), verification by a rescue
/// operator and bounded retention.
///
/// Scope note — this build's Bluetooth packet protocol carries SOS and ACK
/// messages only (`services/ble/packet_codec.dart`). Field reports are stored
/// on the device and merged with any report relayed by another node; they are
/// **not** claimed to have been transmitted, and the UI says so.
library;

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../core/utils/geo.dart';
import '../core/utils/id_generator.dart';
import '../models/enums/flood_severity.dart';
import '../models/flood_report.dart';
import '../repositories/flood_report_repository.dart';

class FloodReportService {
  FloodReportService({
    required this.repository,
    required this.idGenerator,
    DateTime Function()? now,
  }) : _now = now ?? _defaultNow;

  final FloodReportRepository repository;
  final IdGenerator idGenerator;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  /// Validate a proposed report without persisting anything.
  List<String> validateDraft({
    required FloodSeverity severity,
    required WaterDepthCategory waterDepth,
    required int affectedPeople,
    required String description,
    required double latitude,
    required double longitude,
  }) {
    final errors = <String>[];
    if (!isValidCoordinate(latitude, longitude)) {
      errors.add('The reported location is out of range.');
    }
    if (affectedPeople < 0) {
      errors.add('Affected people cannot be negative.');
    }
    if (affectedPeople > Limits.maxPeopleCount) {
      errors.add('Affected people must be at most ${Limits.maxPeopleCount}.');
    }
    if (description.trim().isEmpty) {
      errors.add('Describe what you can see.');
    }
    if (description.trim().length > Limits.maxFieldNoteLength) {
      errors.add(
        'Description must be at most ${Limits.maxFieldNoteLength} characters.',
      );
    }
    return errors;
  }

  /// Persists a new report. The report is complete and readable the moment
  /// this returns; nothing here depends on connectivity.
  Future<FloodReport> createReport({
    required FloodSeverity severity,
    required WaterDepthCategory waterDepth,
    required int affectedPeople,
    required String description,
    required double latitude,
    required double longitude,
    double? accuracy,
    String? reporterId,
    String? reporterName,
    String? photoPath,
  }) async {
    final errors = validateDraft(
      severity: severity,
      waterDepth: waterDepth,
      affectedPeople: affectedPeople,
      description: description,
      latitude: latitude,
      longitude: longitude,
    );
    if (errors.isNotEmpty) throw InvalidFormError(errors);

    final at = _now().toUtc();
    final report = FloodReport(
      reportId: idGenerator.floodReportId(at: at),
      timestamp: at,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      severity: severity,
      waterDepth: waterDepth,
      affectedPeople: affectedPeople,
      description: description.trim(),
      reporterId: reporterId,
      reporterName: reporterName,
      photoPath: photoPath,
    );
    await repository.save(report);
    await prune();
    return report;
  }

  /// Marks a report as confirmed by a rescue operator.
  Future<FloodReport> verify(String reportId) async {
    final existing = await repository.getById(reportId);
    if (existing == null) {
      throw const AppError(
        AppErrorKind.notFound,
        'That flood report is no longer stored on this device.',
      );
    }
    if (existing.verified) return existing;
    final updated = existing.copyWith(verified: true);
    await repository.save(updated);
    return updated;
  }

  Future<void> delete(String reportId) => repository.delete(reportId);

  /// Reports filed inside [Limits.floodReportFreshness], optionally limited to
  /// [radiusMetres] around the given position.
  Future<List<FloodReport>> recent({
    double? latitude,
    double? longitude,
    double radiusMetres = Limits.nearbyRadiusMetres,
  }) {
    return repository.nearby(
      since: _now().toUtc().subtract(Limits.floodReportFreshness),
      latitude: latitude,
      longitude: longitude,
      radiusMetres: radiusMetres,
    );
  }

  /// Highest severity currently reported, or null when nothing is fresh.
  FloodSeverity? peakSeverity(List<FloodReport> reports) {
    FloodSeverity? peak;
    for (final report in reports) {
      if (peak == null || report.severity.weight > peak.weight) {
        peak = report.severity;
      }
    }
    return peak;
  }

  /// Drops entries beyond [Limits.maxStoredReports] and anything older than
  /// [Limits.maxRecordAge]. Returns how many rows were removed.
  Future<int> prune() async {
    final all = await repository.getAll();
    final cutoff = _now().toUtc().subtract(Limits.maxRecordAge);

    final doomed = <String>{};
    for (final report in all) {
      if (report.timestamp.isBefore(cutoff)) doomed.add(report.reportId);
    }

    final survivors = all
        .where((r) => !doomed.contains(r.reportId))
        .toList(growable: false);
    if (survivors.length > Limits.maxStoredReports) {
      // `getAll` is newest-first, so the tail is the oldest.
      for (final report in survivors.sublist(Limits.maxStoredReports)) {
        doomed.add(report.reportId);
      }
    }

    for (final reportId in doomed) {
      await repository.delete(reportId);
    }
    return doomed.length;
  }
}
