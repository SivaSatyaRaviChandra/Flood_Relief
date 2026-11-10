/// Help request application service.
///
/// A help request is what a civilian asks for (food, water, medicine, a lift,
/// a place to sleep). It is deliberately **not** an SOS: an SOS means "get me
/// out now"; a help request means "I need this". Both are stored locally
/// first and both are visible to the same rescue operators.
library;

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../core/utils/geo.dart';
import '../core/utils/id_generator.dart';
import '../models/enums/help_category.dart';
import '../models/help_request.dart';
import '../repositories/help_request_repository.dart';

/// Deterministic urgency for a request.
///
/// The rule is intentionally explicit and inspectable rather than learned: it
/// must be reproducible by a rescue operator reading the record, and the
/// function is unit tested so the mapping can never drift silently.
HelpPriority deriveHelpPriority({
  required HelpCategory category,
  required int peopleCount,
}) {
  final people = peopleCount < 1 ? 1 : peopleCount;
  return switch (category) {
    HelpCategory.rescue => people >= 3 ? HelpPriority.urgent : HelpPriority.high,
    HelpCategory.medical =>
      people >= 2 ? HelpPriority.urgent : HelpPriority.high,
    HelpCategory.drinkingWater =>
      people >= 6 ? HelpPriority.high : HelpPriority.medium,
    HelpCategory.food => people >= 8 ? HelpPriority.high : HelpPriority.medium,
    HelpCategory.shelter =>
      people >= 4 ? HelpPriority.high : HelpPriority.medium,
    HelpCategory.transport =>
      people >= 4 ? HelpPriority.medium : HelpPriority.low,
    HelpCategory.other => people >= 6 ? HelpPriority.medium : HelpPriority.low,
  };
}

/// Allowed status transitions for a help request.
///
/// `cancelled` is reachable from any open state; `fulfilled` only from
/// `inProgress`; the happy path is pending → acknowledged → inProgress →
/// fulfilled.
Set<HelpRequestStatus> allowedHelpTransitions(HelpRequestStatus from) =>
    switch (from) {
      HelpRequestStatus.pending => {
          HelpRequestStatus.acknowledged,
          HelpRequestStatus.inProgress,
          HelpRequestStatus.cancelled,
        },
      HelpRequestStatus.acknowledged => {
          HelpRequestStatus.inProgress,
          HelpRequestStatus.cancelled,
        },
      HelpRequestStatus.inProgress => {
          HelpRequestStatus.fulfilled,
          HelpRequestStatus.cancelled,
        },
      HelpRequestStatus.fulfilled => const {},
      HelpRequestStatus.cancelled => const {},
    };

/// Raised when a request is asked to move to an illegal status.
class InvalidHelpStatusTransition implements Exception {
  const InvalidHelpStatusTransition(this.from, this.to);
  final String from;
  final String to;

  @override
  String toString() =>
      'InvalidHelpStatusTransition: cannot move $from -> $to';
}

class HelpRequestService {
  HelpRequestService({
    required this.repository,
    required this.idGenerator,
    DateTime Function()? now,
  }) : _now = now ?? _defaultNow;

  final HelpRequestRepository repository;
  final IdGenerator idGenerator;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  List<String> validateDraft({
    required HelpCategory category,
    required int peopleCount,
    required String description,
    required double latitude,
    required double longitude,
  }) {
    final errors = <String>[];
    if (!isValidCoordinate(latitude, longitude)) {
      errors.add('The reported location is out of range.');
    }
    if (peopleCount < 1) {
      errors.add('At least one person must be counted.');
    }
    if (peopleCount > Limits.maxPeopleCount) {
      errors.add('People count must be at most ${Limits.maxPeopleCount}.');
    }
    if (description.trim().isEmpty) {
      errors.add('Describe what you need.');
    }
    if (description.trim().length > Limits.maxFieldNoteLength) {
      errors.add(
        'Description must be at most ${Limits.maxFieldNoteLength} characters.',
      );
    }
    return errors;
  }

  Future<HelpRequest> createRequest({
    required HelpCategory category,
    required int peopleCount,
    required String description,
    required double latitude,
    required double longitude,
    double? accuracy,
    String? reporterId,
    String? reporterName,
  }) async {
    final errors = validateDraft(
      category: category,
      peopleCount: peopleCount,
      description: description,
      latitude: latitude,
      longitude: longitude,
    );
    if (errors.isNotEmpty) throw InvalidFormError(errors);

    final at = _now().toUtc();
    final request = HelpRequest(
      requestId: idGenerator.helpRequestId(at: at),
      timestamp: at,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      category: category,
      priority: deriveHelpPriority(
        category: category,
        peopleCount: peopleCount,
      ),
      peopleCount: peopleCount,
      description: description.trim(),
      status: HelpRequestStatus.pending,
      reporterId: reporterId,
      reporterName: reporterName,
      statusUpdatedAt: at,
    );
    await repository.save(request);
    await prune();
    return request;
  }

  Future<HelpRequest> require(String requestId) async {
    final existing = await repository.getById(requestId);
    if (existing == null) {
      throw const AppError(
        AppErrorKind.notFound,
        'That help request is no longer stored on this device.',
      );
    }
    return existing;
  }

  /// Moves [requestId] to [next], refusing illegal transitions.
  Future<HelpRequest> updateStatus(
    String requestId,
    HelpRequestStatus next, {
    String? teamId,
    bool clearTeam = false,
  }) async {
    final existing = await require(requestId);
    if (existing.status == next) return existing;
    if (!allowedHelpTransitions(existing.status).contains(next)) {
      throw InvalidHelpStatusTransition(existing.status.code, next.code);
    }
    final updated = existing.copyWith(
      status: next,
      statusUpdatedAt: _now().toUtc(),
      assignedTeamId: teamId,
      clearAssignedTeam: clearTeam,
    );
    await repository.save(updated);
    return updated;
  }

  /// Acknowledges and assigns [teamId] in one step.
  Future<HelpRequest> acknowledge(String requestId, {String? teamId}) {
    return updateStatus(
      requestId,
      HelpRequestStatus.acknowledged,
      teamId: teamId,
    );
  }

  Future<HelpRequest> startWork(String requestId, {String? teamId}) {
    return updateStatus(
      requestId,
      HelpRequestStatus.inProgress,
      teamId: teamId,
    );
  }

  Future<HelpRequest> fulfil(String requestId, {String? teamId}) {
    return updateStatus(
      requestId,
      HelpRequestStatus.fulfilled,
      teamId: teamId,
    );
  }

  Future<HelpRequest> cancel(String requestId) =>
      updateStatus(requestId, HelpRequestStatus.cancelled, clearTeam: true);

  Future<void> delete(String requestId) => repository.delete(requestId);

  /// Requests filed by [userId], newest first.
  Future<List<HelpRequest>> mine(String userId) async {
    final all = await repository.getAll();
    return all.where((r) => r.reporterId == userId).toList();
  }

  /// Requests within [radiusMetres] of the supplied position.
  Future<List<HelpRequest>> nearby({
    double? latitude,
    double? longitude,
    double radiusMetres = Limits.nearbyRadiusMetres,
  }) {
    return repository.nearby(
      latitude: latitude,
      longitude: longitude,
      radiusMetres: radiusMetres,
    );
  }

  Future<int> prune() async {
    final all = await repository.getAll();
    final cutoff = _now().toUtc().subtract(Limits.maxRecordAge);
    final doomed = <String>{};
    for (final request in all) {
      if (request.timestamp.isBefore(cutoff)) doomed.add(request.requestId);
    }
    final survivors = all
        .where((r) => !doomed.contains(r.requestId))
        .toList(growable: false);
    if (survivors.length > Limits.maxStoredHelpRequests) {
      for (final request in survivors.sublist(Limits.maxStoredHelpRequests)) {
        doomed.add(request.requestId);
      }
    }
    for (final requestId in doomed) {
      await repository.delete(requestId);
    }
    return doomed.length;
  }
}
