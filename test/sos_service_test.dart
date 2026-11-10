/// SOS application service: local-first creation, validation and the status
/// machine.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:flood_relief/core/errors/app_error.dart';
import 'package:flood_relief/models/enums/emergency_type.dart';
import 'package:flood_relief/models/enums/sos_priority.dart';
import 'package:flood_relief/models/enums/sos_status.dart';
import 'package:flood_relief/models/people_info.dart';
import 'package:flood_relief/models/sos_request.dart';
import 'package:flood_relief/models/status_history.dart';
import 'package:flood_relief/repositories/packet_repository.dart';
import 'package:flood_relief/services/ble/packet_codec.dart';
import 'package:flood_relief/services/ble/transmission_queue.dart';
import 'package:flood_relief/services/priority_service.dart';
import 'package:flood_relief/services/sos_service.dart';
import 'package:flood_relief/core/utils/id_generator.dart';

import 'helpers/fakes.dart';

final DateTime fixedNow = DateTime.utc(2026, 9, 22, 12, 0, 0);

void main() {
  late MemorySosRepository sos;
  late MemoryPacketRepository packets;
  late RecordingTransport transport;
  late SosService service;

  setUp(() {
    sos = MemorySosRepository();
    packets = MemoryPacketRepository();
    transport = RecordingTransport();
    final codec = PacketCodec(now: () => fixedNow);
    final queue = TransmissionQueue(
      packetRepository: packets,
      transport: transport,
      codec: codec,
      maxAttempts: 1,
      retryDelay: const Duration(seconds: 1),
    );
    service = SosService(
      sosRepository: sos,
      packetRepository: packets,
      priorityService: const PriorityService(PriorityConfig()),
      idGenerator: IdGenerator(),
      queue: queue,
      originDeviceId: 'DEVICE-ORIG1234',
      now: () => fixedNow,
    );
  });

  SosRequest savedDraft({
    SosStatus status = SosStatus.pending,
    bool acknowledged = false,
  }) {
    final request = SosRequest(
      sosId: 'SOS-20260922-TEST01',
      userId: 'USER-1',
      timestamp: fixedNow,
      latitude: 17.7,
      longitude: 83.3,
      accuracy: 12.0,
      people: const PeopleInfo(totalPeople: 3, childrenCount: 1),
      emergencyType: EmergencyType.rescueRequired,
      description: 'Water rising.',
      priority: SosPriority.high,
      status: status,
      originDeviceId: 'DEVICE-ORIG1234',
      acknowledged: acknowledged,
      acknowledgedAt: acknowledged ? fixedNow : null,
      statusHistory: [
        StatusHistoryEntry(
          previousStatus: null,
          newStatus: SosStatus.pending,
          timestamp: fixedNow,
          actorId: 'USER-1',
          note: 'SOS created and stored on device.',
        ),
      ],
    );
    sos.save(request);
    return request;
  }

  group('createSos', () {
    test('persists locally first, then queues transmission', () async {
      final created = await service.createSos(
        userId: 'USER-1',
        people: const PeopleInfo(totalPeople: 8, childrenCount: 2),
        emergencyType: EmergencyType.rescueRequired,
        description: '  Water rising, people trapped.  ',
        latitude: 17.7,
        longitude: 83.3,
        accuracy: 12.0,
      );

      expect(created.sosId, matches(IdGenerator.sosIdPattern));
      expect(created.status, SosStatus.pending);
      expect(created.priority, SosPriority.critical);
      expect(created.description, 'Water rising, people trapped.');
      expect(created.originDeviceId, 'DEVICE-ORIG1234');

      // Persisted before any transmission.
      final stored = await sos.getById(created.sosId);
      expect(stored, isNotNull);

      // Queued: pending packet exists and one broadcast attempt was made.
      final pending = await packets.pendingPacketIds();
      expect(pending, hasLength(1));
      expect(transport.sent, hasLength(1));
    });

    test('rejects invalid drafts with InvalidFormError', () async {
      expect(
        () => service.createSos(
          userId: 'USER-1',
          people: const PeopleInfo(totalPeople: 0),
          emergencyType: EmergencyType.other,
          description: '',
          latitude: 17.7,
          longitude: 83.3,
        ),
        throwsA(isA<InvalidFormError>()),
      );
    });

    test('does not persist anything when creation fails', () async {
      try {
        await service.createSos(
          userId: 'USER-1',
          people: const PeopleInfo(totalPeople: 0),
          emergencyType: EmergencyType.other,
          description: '',
          latitude: 17.7,
          longitude: 83.3,
        );
        fail('expected InvalidFormError');
      } on InvalidFormError {
        // expected
      }
      expect(await sos.getAll(), isEmpty);
      expect(await packets.pendingPacketIds(), isEmpty);
    });
  });

  group('validateDraft', () {
    test('flags too few people, bad location and oversized description',
        () {
      final errors = service.validateDraft(
        people: const PeopleInfo(totalPeople: 0),
        emergencyType: EmergencyType.other,
        description: 'x' * 601,
        latitude: 95,
        longitude: 83.3,
      );
      expect(errors, isNotEmpty);
      expect(errors.join('\n'), contains('at least 1'));
      expect(errors.join('\n'), contains('600 characters'));
      expect(errors.join('\n'), contains('location is out of range'));
    });

    test('accepts a minimal valid draft', () {
      final errors = service.validateDraft(
        people: const PeopleInfo(totalPeople: 1),
        emergencyType: EmergencyType.other,
        description: 'ok',
        latitude: 17.7,
        longitude: 83.3,
      );
      expect(errors, isEmpty);
    });
  });

  group('transitionStatus', () {
    test('pending → acknowledged records ACK info', () async {
      savedDraft();
      final updated = await service.transitionStatus(
        'SOS-20260922-TEST01',
        SosStatus.acknowledged,
        teamId: 'TEAM-001',
        note: 'ACK received.',
      );
      expect(updated.status, SosStatus.acknowledged);
      expect(updated.acknowledged, isTrue);
      expect(updated.acknowledgedAt, fixedNow);
      expect(updated.statusHistory, hasLength(2));
    });

    test('illegal transitions throw', () async {
      savedDraft();
      expect(
        () => service.transitionStatus(
          'SOS-20260922-TEST01',
          SosStatus.resolved,
        ),
        throwsA(isA<InvalidStatusTransitionError>()),
      );
    });

    test('missing SOS throws an AppError', () async {
      expect(
        () => service.transitionStatus('SOS-NOPE', SosStatus.acknowledged),
        throwsA(isA<AppError>()),
      );
    });
  });

  group('acknowledgeSos', () {
    test('moves a pending SOS to acknowledged', () async {
      savedDraft();
      await service.acknowledgeSos('SOS-20260922-TEST01', teamId: 'RESCUE-1');
      final updated = await sos.getById('SOS-20260922-TEST01');
      expect(updated!.status, SosStatus.acknowledged);
      expect(updated.acknowledgedAt, fixedNow);
    });

    test('is a no-op once acknowledged', () async {
      savedDraft(status: SosStatus.acknowledged, acknowledged: true);
      await service.acknowledgeSos('SOS-20260922-TEST01', teamId: 'RESCUE-1');
      final updated = await sos.getById('SOS-20260922-TEST01');
      expect(updated!.status, SosStatus.acknowledged);
      expect(updated.statusHistory, hasLength(1));
    });

    test('records the flag when status is beyond acknowledged', () async {
      savedDraft(status: SosStatus.inProgress);
      await service.acknowledgeSos('SOS-20260922-TEST01', teamId: 'RESCUE-1');
      final updated = await sos.getById('SOS-20260922-TEST01');
      expect(updated!.status, SosStatus.inProgress); // no backwards move
      expect(updated.acknowledged, isTrue);
      expect(updated.statusHistory, hasLength(2));
    });
  });

  group('rescue workflows', () {
    test('assignTeam sets rescueAssigned + teamId', () async {
      // PENDING cannot skip straight to RESCUE_ASSIGNED per the status
      // machine, so start from ACKNOWLEDGED.
      savedDraft(status: SosStatus.acknowledged);
      final updated = await service.assignTeam(
        'SOS-20260922-TEST01',
        'TEAM-001',
        actorId: 'RESCUE-1',
      );
      expect(updated.status, SosStatus.rescueAssigned);
      expect(updated.assignedTeamId, 'TEAM-001');
    });

    test('startRescue and markResolved complete the lifecycle', () async {
      savedDraft(status: SosStatus.acknowledged);
      final inProgress = await service.startRescue(
        'SOS-20260922-TEST01',
        actorId: 'RESCUE-1',
        teamId: 'TEAM-002',
      );
      expect(inProgress.status, SosStatus.inProgress);
      // Starting directly from ACKNOWLEDGED records the team that responded.
      expect(inProgress.assignedTeamId, 'TEAM-002');

      final resolved = await service.markResolved(
        'SOS-20260922-TEST01',
        actorId: 'RESCUE-1',
      );
      expect(resolved.status, SosStatus.resolved);
      // The assignment is not lost when the incident is closed.
      expect(resolved.assignedTeamId, 'TEAM-002');
    });

    test('the assigned team survives start and resolve', () async {
      savedDraft(status: SosStatus.acknowledged);
      await service.assignTeam('SOS-20260922-TEST01', 'TEAM-001');
      final inProgress =
          await service.startRescue('SOS-20260922-TEST01', actorId: 'RESCUE-1');
      expect(inProgress.status, SosStatus.inProgress);
      expect(inProgress.assignedTeamId, 'TEAM-001');

      final resolved = await service.markResolved(
        'SOS-20260922-TEST01',
        actorId: 'RESCUE-1',
      );
      expect(resolved.status, SosStatus.resolved);
      expect(resolved.assignedTeamId, 'TEAM-001');
      // The acting team is recorded on the later history entries too.
      expect(resolved.statusHistory.last.teamId, 'TEAM-001');
    });
  });
}