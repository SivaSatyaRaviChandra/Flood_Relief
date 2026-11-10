/// SOS application service.
///
/// Owns the business rules for creating SOSs (validation → priority → ID →
/// **save locally first** → queue transmission) and for status transitions.
/// It never touches the database directly — everything goes through
/// repositories.
library;

import '../core/constants/app_constants.dart';
import '../core/errors/app_error.dart';
import '../core/utils/id_generator.dart';
import '../models/enums/emergency_type.dart';
import '../models/enums/sos_priority.dart';
import '../models/enums/sos_status.dart';
import '../models/people_info.dart';
import '../models/sos_packet.dart';
import '../models/sos_request.dart';
import '../models/status_history.dart';
import '../repositories/packet_repository.dart';
import '../repositories/sos_repository.dart';
import '../services/ble/transmission_queue.dart';
import '../services/priority_service.dart';

class SosService {
  SosService({
    required this.sosRepository,
    required this.packetRepository,
    required this.priorityService,
    required this.idGenerator,
    required this.queue,
    required this.originDeviceId,
    DateTime Function()? now,
  }) : _now = now ?? _defaultNow;

  final SosRepository sosRepository;
  final PacketRepository packetRepository;
  final PriorityService priorityService;
  final IdGenerator idGenerator;
  final TransmissionQueue queue;
  final String originDeviceId;
  final DateTime Function() _now;

  static DateTime _defaultNow() => DateTime.now().toUtc();

  /// Validate a proposed SOS payload without persisting anything.
  List<String> validateDraft({
    required PeopleInfo people,
    required EmergencyType emergencyType,
    required String description,
    required double latitude,
    required double longitude,
  }) {
    final errors = <String>[
      ...people.validate(),
    ];
    if (people.totalPeople < Limits.minTotalPeople) {
      errors.add('Total people must be at least ${Limits.minTotalPeople}.');
    }
    if (description.trim().length > Limits.maxDescriptionLength) {
      errors.add(
        'Description must be at most ${Limits.maxDescriptionLength} characters.',
      );
    }
    if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
      errors.add('The captured location is out of range.');
    }
    return errors;
  }

  /// Create + persist an SOS locally, then queue its transmission.
  ///
  /// The SOS is stored BEFORE any transmission is attempted. A positive
  /// return value means the SOS is safely saved on this device even if no
  /// relay/rescue device is reachable.
  Future<SosRequest> createSos({
    required String userId,
    required PeopleInfo people,
    required EmergencyType emergencyType,
    required String description,
    required double latitude,
    required double longitude,
    double? accuracy,
    DateTime? timestamp,
  }) async {
    final errors = validateDraft(
      people: people,
      emergencyType: emergencyType,
      description: description,
      latitude: latitude,
      longitude: longitude,
    );
    if (errors.isNotEmpty) {
      throw InvalidFormError(errors);
    }

    final at = (timestamp ?? _now()).toUtc();

    final verdict = priorityService.evaluate(
      emergencyType: emergencyType,
      people: people,
      description: description,
    );

    final sosId = idGenerator.sosId(at: at);

    final request = SosRequest(
      sosId: sosId,
      userId: userId,
      timestamp: at,
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      people: people,
      emergencyType: emergencyType,
      description: description.trim(),
      priority: verdict.priority,
      status: SosStatus.pending,
      originDeviceId: originDeviceId,
      hopCount: 0,
      acknowledged: false,
      statusHistory: [
        StatusHistoryEntry(
          previousStatus: null,
          newStatus: SosStatus.pending,
          timestamp: at,
          actorId: userId,
          note: 'SOS created and stored on device.',
        ),
      ],
    );

    // CRITICAL: persist before attempting any communication.
    await sosRepository.save(request);

    await queueSosPacket(request);

    return request;
  }

  /// Build, persist and queue the packet for [request] (used on creation and
  /// available for rescue/manual re-dispatch).
  Future<void> queueSosPacket(SosRequest request) async {
    final packet = SosPacketMessage(
      packetId: idGenerator.packetId(),
      sosId: request.sosId,
      originDeviceId: request.originDeviceId,
      senderDeviceId: originDeviceId,
      hopCount: 0,
      ttl: BleConstants.defaultTtl,
      timestamp: _now().toUtc(),
      latitude: request.latitude,
      longitude: request.longitude,
      accuracy: request.accuracy,
      totalPeople: request.people.totalPeople,
      childrenCount: request.people.childrenCount,
      elderlyCount: request.people.elderlyCount,
      pregnantWomenCount: request.people.pregnantWomenCount,
      specialAssistanceCount: request.people.specialAssistanceCount,
      emergencyType: request.emergencyType,
      description: request.description,
      priority: request.priority,
    );
    await queue.enqueue(packet);
  }

  /// Validate + apply a status transition, appending history.
  Future<SosRequest> transitionStatus(
    String sosId,
    SosStatus next, {
    String? actorId,
    String? teamId,
    String? note,
  }) async {
    final request = await sosRepository.getById(sosId);
    if (request == null) {
      throw const AppError(AppErrorKind.notFound, 'SOS not found on this device.');
    }
    if (request.status == next) return request;
    if (!request.status.canTransitionTo(next)) {
      throw InvalidStatusTransitionError(request.status.code, next.code);
    }

    final at = _now().toUtc();

    // `assignedTeamId` records the team an incident is assigned to. It must
    // survive the later transitions: the operator who starts or resolves the
    // rescue is acting on behalf of that same team, and losing the link here
    // would erase the only record of who is responding.
    final assignedTeamId = switch (next) {
      SosStatus.rescueAssigned => teamId ?? request.assignedTeamId,
      SosStatus.inProgress ||
      SosStatus.resolved =>
        request.assignedTeamId ?? teamId,
      _ => request.assignedTeamId,
    };

    final updated = request.copyWith(
      status: next,
      assignedTeamId: assignedTeamId,
      statusHistory: [
        ...request.statusHistory,
        StatusHistoryEntry(
          previousStatus: request.status,
          newStatus: next,
          timestamp: at,
          actorId: actorId,
          teamId: teamId ?? assignedTeamId,
          note: note,
        ),
      ],
      acknowledged: next == SosStatus.acknowledged ? true : request.acknowledged,
      acknowledgedAt: next == SosStatus.acknowledged
          ? at
          : request.acknowledgedAt,
    );
    await sosRepository.save(updated);
    return updated;
  }

  /// Records an ACK for an SOS owned by this device.
  ///
  /// When the SOS is still PENDING the ACK moves it to ACKNOWLEDGED; when it
  /// is already further along only the acknowledgement flag is recorded (the
  /// status machine forbids going backwards).
  Future<void> acknowledgeSos(String sosId, {String? teamId}) async {
    final request = await sosRepository.getById(sosId);
    if (request == null) return;
    if (request.acknowledged) return;

    if (request.status == SosStatus.pending &&
        request.status.canTransitionTo(SosStatus.acknowledged)) {
      await transitionStatus(
        sosId,
        SosStatus.acknowledged,
        actorId: teamId,
        teamId: teamId,
        note: 'ACK received: SOS received by rescue/relay node.',
      );
      return;
    }

    // Status is beyond ACKNOWLEDGED (e.g. directly IN_PROGRESS); record the
    // acknowledgement as a flag + history note without an invalid transition.
    final at = _now().toUtc();
    final updated = request.copyWith(
      acknowledged: true,
      acknowledgedAt: at,
      statusHistory: [
        ...request.statusHistory,
        StatusHistoryEntry(
          previousStatus: request.status,
          newStatus: request.status,
          timestamp: at,
          actorId: teamId,
          teamId: teamId,
          note: 'ACK received while status was ${request.status.label}.',
        ),
      ],
    );
    await sosRepository.save(updated);
  }

  Future<bool> ownsSos(String sosId) async =>
      (await sosRepository.getById(sosId)) != null;

  /// Assign a rescue team, transitioning to RESCUE_ASSIGNED.
  Future<SosRequest> assignTeam(String sosId, String teamId,
      {String? actorId}) async {
    return transitionStatus(
      sosId,
      SosStatus.rescueAssigned,
      actorId: actorId,
      teamId: teamId,
      note: 'Rescue team $teamId assigned.',
    );
  }

  /// Start rescue operations (from PENDING/ACKNOWLEDGED/RESCUE_ASSIGNED).
  Future<SosRequest> startRescue(String sosId,
      {String? actorId, String? teamId}) async {
    final request = await sosRepository.getById(sosId);
    if (request == null) {
      throw const AppError(AppErrorKind.notFound, 'SOS not found on this device.');
    }
    // Directly transitioning from PENDING to IN_PROGRESS is legal per the
    // status machine; acknowledged->inProgress also legal.
    return transitionStatus(
      sosId,
      SosStatus.inProgress,
      actorId: actorId,
      teamId: teamId ?? request.assignedTeamId,
      note: 'Rescue in progress.',
    );
  }

  Future<SosRequest> markResolved(String sosId,
      {String? actorId, String? teamId}) async {
    return transitionStatus(
      sosId,
      SosStatus.resolved,
      actorId: actorId,
      teamId: teamId,
      note: 'SOS resolved.',
    );
  }

  SosPriority priorityOf({
    required EmergencyType emergencyType,
    required PeopleInfo people,
    required String description,
  }) {
    return priorityService
        .evaluate(emergencyType: emergencyType, people: people, description: description)
        .priority;
  }
}