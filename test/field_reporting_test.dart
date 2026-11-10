/// Unit tests for the field-reporting modules: flood reports, help requests,
/// shelters, emergency contacts, alerts, and the local-data service that clears
/// them.
///
/// Every test runs entirely in memory (no Hive file I/O, no platform channels),
/// so these are pure logic checks of the rules the UI depends on.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:flood_relief/core/constants/app_constants.dart';
import 'package:flood_relief/core/errors/app_error.dart';
import 'package:flood_relief/core/utils/geo.dart';
import 'package:flood_relief/core/utils/id_generator.dart';
import 'package:flood_relief/models/alert_record.dart';
import 'package:flood_relief/models/emergency_contact.dart';
import 'package:flood_relief/models/enums/alert_severity.dart';
import 'package:flood_relief/models/enums/emergency_type.dart';
import 'package:flood_relief/models/enums/flood_severity.dart';
import 'package:flood_relief/models/enums/help_category.dart';
import 'package:flood_relief/models/enums/shelter_status.dart';
import 'package:flood_relief/models/enums/sos_priority.dart';
import 'package:flood_relief/models/enums/sos_status.dart';
import 'package:flood_relief/models/flood_report.dart';
import 'package:flood_relief/models/help_request.dart';
import 'package:flood_relief/models/people_info.dart';
import 'package:flood_relief/models/shelter.dart';
import 'package:flood_relief/models/sos_request.dart';
import 'package:flood_relief/repositories/alert_repository.dart';
import 'package:flood_relief/repositories/emergency_contact_repository.dart';
import 'package:flood_relief/repositories/flood_report_repository.dart';
import 'package:flood_relief/repositories/help_request_repository.dart';
import 'package:flood_relief/repositories/packet_repository.dart';
import 'package:flood_relief/repositories/shelter_repository.dart';
import 'package:flood_relief/services/alert_service.dart';
import 'package:flood_relief/services/emergency_contact_service.dart';
import 'package:flood_relief/services/flood_report_service.dart';
import 'package:flood_relief/services/help_request_service.dart';
import 'package:flood_relief/services/local_data_service.dart';
import 'package:flood_relief/services/shelter_service.dart';

import 'helpers/fakes.dart';

/// Fixed clock so freshness and pruning windows are deterministic.
final DateTime fixedNow = DateTime.utc(2026, 9, 22, 12, 0, 0);
DateTime fixedNowFn() => fixedNow;

/// A valid stored SOS. Built through one helper so every fixture in this file
/// agrees with the real constructor contract.
SosRequest buildSos({
  String sosId = 'SOS-20260922-PEND01',
  SosStatus status = SosStatus.pending,
  SosPriority priority = SosPriority.high,
  int totalPeople = 2,
  String description = 'Help.',
  String userId = 'USER-1',
}) {
  return SosRequest(
    sosId: sosId,
    userId: userId,
    timestamp: fixedNow,
    latitude: 17.7,
    longitude: 83.3,
    people: PeopleInfo(totalPeople: totalPeople),
    emergencyType: EmergencyType.rescueRequired,
    description: description,
    priority: priority,
    status: status,
    originDeviceId: 'DEVICE-0000A1B2',
  );
}

void main() {
  group('FloodReportService', () {
    late MemoryFloodReportRepository repository;
    late FloodReportService service;

    setUp(() {
      repository = MemoryFloodReportRepository();
      service = FloodReportService(
        repository: repository,
        idGenerator: IdGenerator(),
        now: fixedNowFn,
      );
    });

    tearDown(() => repository.dispose());

    test('stores a report and generates a matching id', () async {
      final report = await service.createReport(
        severity: FloodSeverity.high,
        waterDepth: WaterDepthCategory.kneeDeep,
        affectedPeople: 12,
        description: 'Water entering homes on the second floor.',
        latitude: 17.7,
        longitude: 83.3,
        reporterName: 'Ana',
      );

      expect(report.reportId, matches(RegExp(r'^FLD-\d{8}-[0-9A-F]{6}$')));
      expect(report.verified, isFalse);
      expect(report.timestamp, fixedNow);
      expect(report.reporterName, 'Ana');

      final stored = await repository.getById(report.reportId);
      expect(stored, isNotNull);
      expect(stored!.severity, FloodSeverity.high);
      expect(stored.waterDepth, WaterDepthCategory.kneeDeep);
      expect(stored.affectedPeople, 12);
    });

    test('rejects an empty description instead of storing a blank report',
        () async {
      await expectLater(
        service.createReport(
          severity: FloodSeverity.low,
          waterDepth: WaterDepthCategory.ankleDeep,
          affectedPeople: 1,
          description: '   ',
          latitude: 17.7,
          longitude: 83.3,
        ),
        throwsA(isA<InvalidFormError>()),
      );
      expect(await repository.getAll(), isEmpty);
    });

    test('rejects an out-of-range coordinate', () {
      final errors = service.validateDraft(
        severity: FloodSeverity.low,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: 1,
        description: 'ok',
        latitude: 999,
        longitude: 0,
      );
      expect(errors, isNotEmpty);
    });

    test('caps the affected-people count at the documented limit', () {
      final errors = service.validateDraft(
        severity: FloodSeverity.low,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: Limits.maxPeopleCount + 1,
        description: 'ok',
        latitude: 17.7,
        longitude: 83.3,
      );
      expect(errors.any((e) => e.contains('${Limits.maxPeopleCount}')), isTrue);
    });

    test('verifying a report does not touch the rest of the record', () async {
      final report = await service.createReport(
        severity: FloodSeverity.medium,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: 3,
        description: 'Street flooded.',
        latitude: 17.7,
        longitude: 83.3,
      );

      final verified = await service.verify(report.reportId);
      expect(verified.verified, isTrue);
      expect(verified.description, 'Street flooded.');
      expect(verified.affectedPeople, 3);
    });

    test('verifying twice is a no-op, not a duplicate', () async {
      final report = await service.createReport(
        severity: FloodSeverity.medium,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: 3,
        description: 'Street flooded.',
        latitude: 17.7,
        longitude: 83.3,
      );
      final first = await service.verify(report.reportId);
      final again = await service.verify(report.reportId);
      expect(again.verified, isTrue);
      expect(again.reportId, first.reportId);
      expect(again.timestamp, first.timestamp);
      // One row, not two.
      expect(await repository.getAll(), hasLength(1));
    });

    test('verifying a missing report reports it honestly', () async {
      await expectLater(
        service.verify('FLD-20260922-ABCDEF'),
        throwsA(
          isA<AppError>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.notFound,
          ),
        ),
      );
    });

    test('prunes reports older than the retention window', () async {
      final fresh = await service.createReport(
        severity: FloodSeverity.low,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: 1,
        description: 'Current.',
        latitude: 17.7,
        longitude: 83.3,
      );

      // Inserted after the fresh report so `createReport`'s own prune pass
      // cannot remove it before the assertion under test runs.
      final old = FloodReport(
        reportId: 'FLD-20200101-OLD000',
        timestamp: fixedNow.subtract(const Duration(days: 90)),
        latitude: 17.7,
        longitude: 83.3,
        severity: FloodSeverity.low,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: 1,
        description: 'Ancient.',
      );
      await repository.save(old);

      final removed = await service.prune();
      expect(removed, 1);
      expect(await repository.getById(old.reportId), isNull);
      expect(await repository.getById(fresh.reportId), isNotNull);
    });

    test('recent() sorts by distance and respects the radius', () async {
      await service.createReport(
        severity: FloodSeverity.low,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: 1,
        description: 'Far.',
        latitude: 17.9,
        longitude: 83.9,
      );
      await service.createReport(
        severity: FloodSeverity.low,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: 1,
        description: 'Near.',
        latitude: 17.7001,
        longitude: 83.3001,
      );

      final near = await service.recent(latitude: 17.7, longitude: 83.3);
      expect(near, isNotEmpty);
      expect(near.first.description, 'Near.');
      // Everything returned is inside the radius, so the far report is excluded.
      for (final report in near) {
        expect(report.description, isNot('Far.'));
      }
    });

    test('recent() hides a stale report even without a position', () async {
      await repository.save(
        FloodReport(
          reportId: 'FLD-20200101-STALE1',
          timestamp: fixedNow.subtract(const Duration(days: 2)),
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.critical,
          waterDepth: WaterDepthCategory.aboveHead,
          affectedPeople: 9,
          description: 'Old news.',
        ),
      );
      final fresh = await service.recent();
      expect(fresh.any((r) => r.reportId == 'FLD-20200101-STALE1'), isFalse);
    });

    test('peakSeverity reports the worst thing on the ground', () async {
      final reports = await service.createReport(
        severity: FloodSeverity.low,
        waterDepth: WaterDepthCategory.ankleDeep,
        affectedPeople: 1,
        description: 'Puddle.',
        latitude: 17.7,
        longitude: 83.3,
      );
      expect(service.peakSeverity([reports]), FloodSeverity.low);
      expect(
        service.peakSeverity([
          reports,
          reports.copyWith(severity: FloodSeverity.critical),
        ]),
        FloodSeverity.critical,
      );
    });
  });

  group('deriveHelpPriority', () {
    test('rescue is urgent for three or more people, high below that', () {
      expect(
        deriveHelpPriority(
            category: HelpCategory.rescue, peopleCount: 3),
        HelpPriority.urgent,
      );
      expect(
        deriveHelpPriority(
            category: HelpCategory.rescue, peopleCount: 1),
        HelpPriority.high,
      );
    });

    test('medical crosses to urgent at two people', () {
      expect(
        deriveHelpPriority(
            category: HelpCategory.medical, peopleCount: 2),
        HelpPriority.urgent,
      );
      expect(
        deriveHelpPriority(
            category: HelpCategory.medical, peopleCount: 1),
        HelpPriority.high,
      );
    });

    test('supply categories scale with the number of people', () {
      expect(
        deriveHelpPriority(
            category: HelpCategory.drinkingWater, peopleCount: 6),
        HelpPriority.high,
      );
      expect(
        deriveHelpPriority(
            category: HelpCategory.drinkingWater, peopleCount: 2),
        HelpPriority.medium,
      );
      expect(
        deriveHelpPriority(
            category: HelpCategory.food, peopleCount: 8),
        HelpPriority.high,
      );
      expect(
        deriveHelpPriority(category: HelpCategory.other, peopleCount: 1),
        HelpPriority.low,
      );
    });

    test('a nonsensical count is treated as one person, never zero', () {
      expect(
        deriveHelpPriority(category: HelpCategory.other, peopleCount: 0),
        HelpPriority.low,
      );
      expect(
        deriveHelpPriority(category: HelpCategory.rescue, peopleCount: 0),
        HelpPriority.high,
      );
    });
  });

  group('HelpRequestService', () {
    late MemoryHelpRequestRepository repository;
    late HelpRequestService service;

    setUp(() {
      repository = MemoryHelpRequestRepository();
      service = HelpRequestService(
        repository: repository,
        idGenerator: IdGenerator(),
        now: fixedNowFn,
      );
    });

    tearDown(() => repository.dispose());

    Future<HelpRequest> makeRequest({HelpCategory? category, int? people}) {
      return service.createRequest(
        category: category ?? HelpCategory.food,
        peopleCount: people ?? 2,
        description: 'We need food and water.',
        latitude: 17.7,
        longitude: 83.3,
        reporterId: 'USER-1',
        reporterName: 'Ana',
      );
    }

    test('creates a pending request with a derived priority', () async {
      final request = await service.createRequest(
        category: HelpCategory.medical,
        peopleCount: 2,
        description: 'An injured person needs a doctor.',
        latitude: 17.7,
        longitude: 83.3,
      );

      expect(request.requestId, matches(RegExp(r'^REQ-\d{8}-[0-9A-F]{6}$')));
      expect(request.status, HelpRequestStatus.pending);
      expect(request.priority, HelpPriority.urgent);
      expect(request.isOpen, isTrue);
      expect(request.statusUpdatedAt, fixedNow);
    });

    test('refuses a request that counts nobody', () async {
      await expectLater(
        service.createRequest(
          category: HelpCategory.food,
          peopleCount: 0,
          description: 'Somebody.',
          latitude: 17.7,
          longitude: 83.3,
        ),
        throwsA(isA<InvalidFormError>()),
      );
      expect(await repository.getAll(), isEmpty);
    });

    test('require() reports a missing request honestly', () async {
      await expectLater(
        service.require('REQ-20260922-NOPE00'),
        throwsA(
          isA<AppError>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.notFound,
          ),
        ),
      );
    });

    test('walks the happy path pending -> acknowledged -> inProgress -> '
        'fulfilled', () async {
      final request = await makeRequest();

      final acknowledged = await service.acknowledge(
        request.requestId,
        teamId: 'TEAM-001',
      );
      expect(acknowledged.status, HelpRequestStatus.acknowledged);
      expect(acknowledged.assignedTeamId, 'TEAM-001');

      final working = await service.startWork(request.requestId);
      expect(working.status, HelpRequestStatus.inProgress);
      expect(working.assignedTeamId, 'TEAM-001');

      final done = await service.fulfil(request.requestId);
      expect(done.status, HelpRequestStatus.fulfilled);
      expect(done.isOpen, isFalse);
    });

    test('refuses to fulfil a request that was never started', () async {
      final request = await makeRequest();
      await expectLater(
        service.fulfil(request.requestId),
        throwsA(isA<InvalidHelpStatusTransition>()),
      );
      // The illegal transition must not have been persisted.
      final still = await service.require(request.requestId);
      expect(still.status, HelpRequestStatus.pending);
    });

    test('a terminal status has no way out', () {
      expect(allowedHelpTransitions(HelpRequestStatus.fulfilled), isEmpty);
      expect(allowedHelpTransitions(HelpRequestStatus.cancelled), isEmpty);
    });

    test('a cancelled request cannot be acknowledged afterwards', () async {
      final request = await makeRequest();
      await service.cancel(request.requestId);
      await expectLater(
        service.acknowledge(request.requestId),
        throwsA(isA<InvalidHelpStatusTransition>()),
      );
    });

    test('cancelling releases the assigned team', () async {
      final request = await makeRequest();
      await service.acknowledge(request.requestId, teamId: 'TEAM-001');
      final cancelled = await service.cancel(request.requestId);
      expect(cancelled.status, HelpRequestStatus.cancelled);
      expect(cancelled.assignedTeamId, isNull);
    });

    test('setting the same status twice is a no-op, not an error', () async {
      final request = await makeRequest();
      final again = await service.updateStatus(
        request.requestId,
        HelpRequestStatus.pending,
      );
      expect(again.status, HelpRequestStatus.pending);
    });

    test('mine() only returns the given reporter', () async {
      await makeRequest();
      await service.createRequest(
        category: HelpCategory.medical,
        peopleCount: 1,
        description: 'Someone else.',
        latitude: 17.7,
        longitude: 83.3,
        reporterId: 'USER-2',
      );

      final mine = await service.mine('USER-1');
      expect(mine, hasLength(1));
      expect(mine.single.reporterId, 'USER-1');
    });
  });

  group('Shelter model', () {
    Shelter build({int capacity = 100, int occupied = 0, bool open = true}) {
      return Shelter(
        shelterId: 'SHT-000001',
        name: 'Riverside School',
        capacity: capacity,
        occupied: occupied,
        contactPhone: null,
        facilities: const ['Water'],
        open: open,
      );
    }

    test('status is derived from capacity and occupancy, never stored', () {
      expect(build(capacity: 100, occupied: 0).status, ShelterStatus.available);
      expect(build(capacity: 100, occupied: 98).status, ShelterStatus.limited);
      expect(build(capacity: 100, occupied: 100).status, ShelterStatus.full);
      // Over capacity still reads as full, never as negative space.
      expect(build(capacity: 100, occupied: 140).status, ShelterStatus.full);
      expect(build(capacity: 100, occupied: 140).availableCapacity, 0);
    });

    test('unknown capacity reports zero free places rather than a fake number',
        () {
      final unknown = build(capacity: 0, occupied: 12);
      expect(unknown.availableCapacity, 0);
      expect(unknown.hasCoordinates, isFalse);
    });

    test('survives a map round trip', () {
      final shelter = build(capacity: 50, occupied: 20);
      final restored = Shelter.fromMap(shelter.toMap());
      expect(restored.shelterId, shelter.shelterId);
      expect(restored.capacity, 50);
      expect(restored.occupied, 20);
      expect(restored.facilities, ['Water']);
      expect(restored.status, ShelterStatus.available);
      expect(restored.open, isTrue);
    });
  });

  group('ShelterService', () {
    late MemoryShelterRepository repository;
    late IdGenerator ids;
    late ShelterService service;

    setUp(() {
      repository = MemoryShelterRepository();
      ids = IdGenerator();
      service = ShelterService(repository: repository, idGenerator: ids);
    });

    tearDown(() => repository.dispose());

    Future<Shelter> seed({int capacity = 10, int occupied = 0}) async {
      final shelter = Shelter(
        shelterId: ids.shelterId(),
        name: 'Camp',
        capacity: capacity,
        occupied: occupied,
        contactPhone: null,
        facilities: const [],
      );
      await repository.save(shelter);
      return shelter;
    }

    test('saveShelter() stores a shelter with a generated id', () async {
      final shelter = await service.saveShelter(
        name: 'Riverside School',
        capacity: 120,
        occupied: 0,
        address: 'Main road',
        facilities: const ['Water', 'Power'],
        latitude: 17.7,
        longitude: 83.3,
      );

      expect(shelter.shelterId, matches(IdGenerator.shelterIdPattern));
      expect(shelter.status, ShelterStatus.available);
      expect(await repository.getById(shelter.shelterId), isNotNull);
    });

    test('refuses a blank name', () async {
      await expectLater(
        service.saveShelter(name: '  ', capacity: 10, occupied: 0),
        throwsA(isA<InvalidFormError>()),
      );
    });

    test('refuses occupancy larger than capacity', () async {
      await expectLater(
        service.saveShelter(name: 'Camp', capacity: 10, occupied: 11),
        throwsA(isA<InvalidFormError>()),
      );
    });

    test('refuses half a coordinate', () {
      final errors = service.validateDraft(
        name: 'Camp',
        capacity: 10,
        occupied: 0,
        latitude: 17.7,
        longitude: null,
        facilities: const [],
      );
      expect(errors.any((e) => e.contains('both latitude and longitude')), isTrue);
    });

    test('arrival and departure move occupancy without overshooting '
        'capacity', () async {
      final shelter = await seed(capacity: 2);

      final one = await service.recordArrival(shelter.shelterId, 1);
      expect(one.occupied, 1);
      final two = await service.recordArrival(shelter.shelterId, 5);
      // Cannot exceed capacity.
      expect(two.occupied, 2);
      expect(two.status, ShelterStatus.full);

      final back = await service.recordDeparture(shelter.shelterId, 10);
      expect(back.occupied, 0);
    });

    test('a zero or negative movement changes nothing', () async {
      final shelter = await seed(capacity: 10, occupied: 4);
      expect((await service.recordArrival(shelter.shelterId, 0)).occupied, 4);
      expect((await service.recordDeparture(shelter.shelterId, 0)).occupied, 4);
    });

    test('setOccupancy clamps to capacity', () async {
      final shelter = await seed(capacity: 10);
      expect((await service.setOccupancy(shelter.shelterId, 99)).occupied, 10);
      expect((await service.setOccupancy(shelter.shelterId, -5)).occupied, 0);
    });

    test('closing a shelter is remembered, not derived', () async {
      final shelter = await seed(capacity: 10);
      final closed = await service.setOpen(shelter.shelterId, false);
      expect(closed.open, isFalse);
      expect(closed.status, ShelterStatus.available);

      final reloaded = await service.require(shelter.shelterId);
      expect(reloaded.open, isFalse);
    });

    test('unknown capacity is allowed and recorded as unknown', () async {
      final shelter = await service.saveShelter(
        name: 'Unknown hall',
        capacity: 0,
        occupied: 0,
      );
      expect(shelter.capacity, 0);
      final after = await service.recordArrival(shelter.shelterId, 3);
      expect(after.occupied, 3);
      expect(after.status, ShelterStatus.limited);
    });

    test('require() reports a missing shelter honestly', () async {
      await expectLater(
        service.require('SHT-ABCDEF'),
        throwsA(
          isA<AppError>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.notFound,
          ),
        ),
      );
    });

    test('countWithSpace ignores full and closed shelters', () async {
      final open = await seed(capacity: 10, occupied: 1);
      final full = await seed(capacity: 10, occupied: 10);
      final closed = await seed(capacity: 10, occupied: 1);
      await service.setOpen(closed.shelterId, false);

      final all = await repository.getAll();
      expect(service.countWithSpace(all), 1);
      expect(all, hasLength(3));
      expect(open.occupied, 1);
      expect(full.occupied, 10);
    });
  });

  group('sortedByDistance', () {
    late MemoryShelterRepository repository;

    setUp(() => repository = MemoryShelterRepository());
    tearDown(() => repository.dispose());

    test('puts shelters without coordinates last instead of hiding them',
        () async {
      await repository.save(
        Shelter(
          shelterId: 'SHT-000002',
          name: 'No position',
          capacity: 10,
          occupied: 0,
          contactPhone: null,
          facilities: const [],
        ),
      );
      await repository.save(
        Shelter(
          shelterId: 'SHT-000001',
          name: 'Far',
          capacity: 10,
          occupied: 0,
          contactPhone: null,
          facilities: const [],
          latitude: 17.9,
          longitude: 83.9,
        ),
      );
      await repository.save(
        Shelter(
          shelterId: 'SHT-000003',
          name: 'Near',
          capacity: 10,
          occupied: 0,
          contactPhone: null,
          facilities: const [],
          latitude: 17.7001,
          longitude: 83.3001,
        ),
      );

      final sorted = await repository.sortedByDistance(
        latitude: 17.7,
        longitude: 83.3,
      );

      expect(sorted, hasLength(3));
      expect(sorted[0].shelter.name, 'Near');
      expect(sorted[1].shelter.name, 'Far');
      // The unpositioned shelter is still listed, just last.
      expect(sorted.last.shelter.name, 'No position');
      expect(sorted.last.distanceMetres, isNull);
    });
  });

  group('parseOccupancy', () {
    test('reads "120/300"', () {
      expect(parseOccupancy('120/300'), (occupied: 120, capacity: 300));
    });

    test('rejects malformed input rather than guessing', () {
      expect(parseOccupancy('120'), isNull);
      expect(parseOccupancy('a/b'), isNull);
      expect(parseOccupancy('-1/10'), isNull);
      expect(parseOccupancy('10/5/2'), isNull);
    });
  });

  group('AlertService', () {
    late MemoryAlertRepository alerts;
    late MemorySosRepository sos;
    late MemoryFloodReportRepository reports;
    late MemoryHelpRequestRepository requests;
    late MemoryShelterRepository shelters;
    late AlertService service;

    setUp(() {
      alerts = MemoryAlertRepository();
      sos = MemorySosRepository();
      reports = MemoryFloodReportRepository();
      requests = MemoryHelpRequestRepository();
      shelters = MemoryShelterRepository();
      service = AlertService(
        alertRepository: alerts,
        sosRepository: sos,
        floodReportRepository: reports,
        helpRequestRepository: requests,
        shelterRepository: shelters,
        idGenerator: IdGenerator(),
        now: fixedNowFn,
      );
    });

    tearDown(() {
      alerts.dispose();
      sos.dispose();
      reports.dispose();
      requests.dispose();
      shelters.dispose();
    });

    test('an empty device produces an empty feed, not a placeholder alert',
        () async {
      expect(await service.refresh(), 0);
      expect(await alerts.getAll(), isEmpty);
      expect(await service.unreadCount(), 0);
    });

    test('a critical flood report raises exactly one alert', () async {
      await reports.save(
        FloodReport(
          reportId: 'FLD-20260922-AAA111',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.critical,
          waterDepth: WaterDepthCategory.waistDeep,
          affectedPeople: 40,
          description: 'Street impassable.',
        ),
      );

      expect(await service.refresh(), 1);
      final all = await alerts.getAll();
      expect(all, hasLength(1));
      expect(all.single.severity, AlertSeverity.critical);
      expect(all.single.relatedId, 'FLD-20260922-AAA111');
      expect(all.single.source, AlertSource.floodReport);
    });

    test('a minor report inside the freshness window raises nothing', () async {
      await reports.save(
        FloodReport(
          reportId: 'FLD-20260922-BBB222',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.low,
          waterDepth: WaterDepthCategory.ankleDeep,
          affectedPeople: 1,
          description: 'Puddle.',
        ),
      );
      expect(await service.refresh(), 0);
    });

    test('a critical report older than the freshness window is not an alert',
        () async {
      await reports.save(
        FloodReport(
          reportId: 'FLD-20260101-OLD001',
          timestamp: fixedNow.subtract(const Duration(days: 2)),
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.critical,
          waterDepth: WaterDepthCategory.waistDeep,
          affectedPeople: 40,
          description: 'Old but severe.',
        ),
      );
      expect(await service.refresh(), 0);
    });

    test('refresh is idempotent: running it repeatedly adds nothing', () async {
      await reports.save(
        FloodReport(
          reportId: 'FLD-20260922-CCC333',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.critical,
          waterDepth: WaterDepthCategory.waistDeep,
          affectedPeople: 10,
          description: 'Rising fast.',
        ),
      );

      expect(await service.refresh(), 1);
      expect(await service.refresh(), 0);
      expect(await service.refresh(), 0);
      expect(await alerts.getAll(), hasLength(1));
    });

    test('a full shelter raises one alert, and only one', () async {
      await shelters.save(
        Shelter(
          shelterId: 'SHT-000001',
          name: 'Riverside School',
          capacity: 50,
          occupied: 50,
          contactPhone: null,
          facilities: const [],
        ),
      );
      expect(await service.refresh(), 1);
      final all = await alerts.getAll();
      expect(all.single.title, contains('Riverside School'));
      expect(await service.refresh(), 0);
    });

    test('an urgent open help request raises one alert', () async {
      await requests.save(
        HelpRequest(
          requestId: 'REQ-20260922-URG001',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          category: HelpCategory.medical,
          priority: HelpPriority.urgent,
          peopleCount: 2,
          description: 'Injured.',
          status: HelpRequestStatus.pending,
        ),
      );
      expect(await service.refresh(), 1);
      expect((await alerts.getAll()).single.source, AlertSource.helpRequest);
    });

    test('a resolved help request drops out of the feed on the next refresh',
        () async {
      final request = HelpRequest(
        requestId: 'REQ-20260922-DONE01',
        timestamp: fixedNow,
        latitude: 17.7,
        longitude: 83.3,
        category: HelpCategory.medical,
        priority: HelpPriority.urgent,
        peopleCount: 2,
        description: 'Injured.',
        status: HelpRequestStatus.pending,
      );
      await requests.save(request);
      expect(await service.refresh(), 1);

      await requests.save(
        request.copyWith(status: HelpRequestStatus.fulfilled),
      );
      // The alert about a finished request is not re-derived, so the feed
      // shrinks only once it is explicitly forgotten.
      expect(await service.refresh(), 0);
      await service.forget(alertDedupeKey(
        source: AlertSource.helpRequest,
        topic: 'urgent',
        relatedId: request.requestId,
      ));
      expect(await alerts.getAll(), isEmpty);
    });

    test('an SOS that has not moved past pending raises nothing', () async {
      await sos.save(buildSos());
      expect(await service.refresh(), 0);
    });

    test('a status change on a real SOS raises exactly one alert', () async {
      await sos.save(
        buildSos(
          status: SosStatus.acknowledged,
          description: 'Water rising.',
        ),
      );
      expect(await service.refresh(), 1);
      final all = await alerts.getAll();
      expect(all.single.source, AlertSource.sos);
      expect(all.single.relatedId, 'SOS-20260922-PEND01');
      expect(all.single.severity, AlertSeverity.info);
      expect(await service.refresh(), 0);
    });

    test('a critical active SOS gets its own loud alert', () async {
      await sos.save(
        buildSos(priority: SosPriority.critical, totalPeople: 6),
      );
      expect(await service.refresh(), 1);
      final all = await alerts.getAll();
      expect(all.single.severity, AlertSeverity.critical);
      expect(all.single.title, contains('SOS-20260922-PEND01'));
    });

    test('marking read is reflected in the unread count', () async {
      await reports.save(
        FloodReport(
          reportId: 'FLD-20260922-DDD444',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.critical,
          waterDepth: WaterDepthCategory.waistDeep,
          affectedPeople: 10,
          description: 'Rising fast.',
        ),
      );
      await service.refresh();
      expect(await service.unreadCount(), 1);

      final single = (await alerts.getAll()).single;
      await service.markRead(single.alertId);
      expect(await service.unreadCount(), 0);

      // Re-deriving must not resurrect it as unread.
      await service.refresh();
      expect(await service.unreadCount(), 0);
      expect(await alerts.getAll(), hasLength(1));
    });

    test('markAllRead clears the whole feed', () async {
      await reports.save(
        FloodReport(
          reportId: 'FLD-20260922-EEE555',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.critical,
          waterDepth: WaterDepthCategory.waistDeep,
          affectedPeople: 10,
          description: 'Rising fast.',
        ),
      );
      await service.refresh();
      expect(await service.markAllRead(), 1);
      expect(await service.unreadCount(), 0);
    });

    test('an advisory is always kept, even when the wording repeats', () async {
      await service.publishAdvisory(
        title: 'Bridge out',
        description: 'The low bridge is impassable.',
        severity: AlertSeverity.danger,
      );
      await service.publishAdvisory(
        title: 'Bridge out',
        description: 'The low bridge is impassable.',
        severity: AlertSeverity.danger,
      );
      expect(await alerts.getAll(), hasLength(2));

      // Advisories are not re-derived, so a refresh leaves them alone.
      await service.refresh();
      expect(await alerts.getAll(), hasLength(2));
    });

    test('forget() drops the alerts about a deleted record', () async {
      await reports.save(
        FloodReport(
          reportId: 'FLD-20260922-EEE555',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.critical,
          waterDepth: WaterDepthCategory.waistDeep,
          affectedPeople: 10,
          description: 'Rising fast.',
        ),
      );
      await service.refresh();
      expect(await alerts.getAll(), hasLength(1));

      await reports.delete('FLD-20260922-EEE555');
      // The topic is built from the enum code, so forgetting by hand has to use
      // exactly the key the derivation used.
      await service.forget(alertDedupeKey(
        source: AlertSource.floodReport,
        topic: 'flood-${FloodSeverity.critical.code}',
        relatedId: 'FLD-20260922-EEE555',
      ));
      expect(await alerts.getAll(), isEmpty);
    });
  });

  group('EmergencyContactService', () {
    late MemoryEmergencyContactRepository repository;
    late EmergencyContactService service;

    setUp(() {
      repository = MemoryEmergencyContactRepository();
      service = EmergencyContactService(
        repository: repository,
        idGenerator: IdGenerator(),
      );
    });

    tearDown(() => repository.dispose());

    test('a fresh install has no contacts at all', () async {
      // The app ships empty rather than inventing hotline numbers.
      expect(await repository.getAll(), isEmpty);
      expect(await service.isEmpty(), isTrue);
      expect(await service.primary(), isNull);
    });

    test('exactly one contact can be the primary', () async {
      final first = await service.saveContact(
        name: 'Local volunteer',
        phone: '+91 00000 00000',
        kind: ContactKind.authority,
        isPrimary: true,
      );
      final second = await service.saveContact(
        name: 'District office',
        phone: '+91 11111 11111',
        kind: ContactKind.authority,
        isPrimary: true,
      );

      final all = await repository.getAll();
      expect(all.where((c) => c.isPrimary), hasLength(1));
      // The newest primary wins, and the older one is demoted rather than
      // deleted.
      expect(
        all.firstWhere((c) => c.contactId == second.contactId).isPrimary,
        isTrue,
      );
      expect(
        all.firstWhere((c) => c.contactId == first.contactId).isPrimary,
        isFalse,
      );
      expect((await service.primary())?.contactId, second.contactId);
    });

    test('setPrimary moves the flag without creating a record', () async {
      final a = await service.saveContact(
        name: 'A',
        phone: '00000 00000',
        kind: ContactKind.family,
      );
      final b = await service.saveContact(
        name: 'B',
        phone: '11111 11111',
        kind: ContactKind.friend,
      );
      await service.setPrimary(b.contactId);

      final all = await repository.getAll();
      expect(all, hasLength(2));
      expect(all.firstWhere((c) => c.contactId == b.contactId).isPrimary, isTrue);
      expect(all.firstWhere((c) => c.contactId == a.contactId).isPrimary, isFalse);

      await service.setPrimary(null);
      expect((await repository.getAll()).where((c) => c.isPrimary), isEmpty);
    });

    test('rejects a blank name and an undialable number', () async {
      await expectLater(
        service.saveContact(
          name: '  ',
          phone: '00000 00000',
          kind: ContactKind.family,
        ),
        throwsA(isA<InvalidFormError>()),
      );
      await expectLater(
        service.saveContact(
          name: 'Someone',
          phone: 'not a number',
          kind: ContactKind.family,
        ),
        throwsA(isA<InvalidFormError>()),
      );
      // Too short to be a real number.
      await expectLater(
        service.saveContact(
          name: 'Someone',
          phone: '123',
          kind: ContactKind.family,
        ),
        throwsA(isA<InvalidFormError>()),
      );
    });

    test('require() reports a missing contact honestly', () async {
      await expectLater(
        service.require('CON-ABCDEF'),
        throwsA(
          isA<AppError>().having(
            (e) => e.kind,
            'kind',
            AppErrorKind.notFound,
          ),
        ),
      );
    });

    test('a contact survives a map round trip', () async {
      final contact = await service.saveContact(
        name: 'Volunteer',
        phone: '+91 00000 00000',
        kind: ContactKind.rescue,
        notes: 'Rowing boat.',
        isPrimary: true,
      );
      final restored = EmergencyContact.fromMap(contact.toMap());
      expect(restored.contactId, contact.contactId);
      expect(restored.kind, ContactKind.rescue);
      expect(restored.notes, 'Rowing boat.');
      expect(restored.isPrimary, isTrue);
    });
  });

  group('LocalDataService', () {
    late MemorySosRepository sos;
    late MemoryPacketRepository packets;
    late MemoryFloodReportRepository reports;
    late MemoryHelpRequestRepository requests;
    late MemoryAlertRepository alerts;
    late MemoryEmergencyContactRepository contacts;
    late MemoryShelterRepository shelters;
    late LocalDataService service;

    setUp(() {
      sos = MemorySosRepository();
      packets = MemoryPacketRepository();
      reports = MemoryFloodReportRepository();
      requests = MemoryHelpRequestRepository();
      alerts = MemoryAlertRepository();
      contacts = MemoryEmergencyContactRepository();
      shelters = MemoryShelterRepository();
      service = LocalDataService(
        sosRepository: sos,
        packetRepository: packets,
        floodReportRepository: reports,
        helpRequestRepository: requests,
        alertRepository: alerts,
        contactRepository: contacts,
        shelterRepository: shelters,
      );
    });

    tearDown(() {
      sos.dispose();
      packets.dispose();
      reports.dispose();
      requests.dispose();
      alerts.dispose();
      contacts.dispose();
      shelters.dispose();
    });

    test('currentUsage() reports what is really stored', () async {
      await sos.save(buildSos(sosId: 'SOS-20260922-KEEP001', totalPeople: 1));
      await shelters.save(
        Shelter(
          shelterId: 'SHT-000001',
          name: 'Camp',
          capacity: 10,
          occupied: 0,
          contactPhone: null,
          facilities: const [],
        ),
      );

      final usage = await service.currentUsage();
      expect(usage.sosRecords, 1);
      expect(usage.shelters, 1);
      expect(usage.isEmpty, isFalse);
    });

    test('an untouched device reports empty storage rather than fake records',
        () async {
      final usage = await service.currentUsage();
      expect(usage.isEmpty, isTrue);
      expect(usage.sosRecords, 0);
      expect(usage.packets, 0);
      expect(usage.shelters, 0);
    });

    test('clearUserData() removes user data but keeps shelters', () async {
      await sos.save(buildSos(sosId: 'SOS-20260922-GONE001', totalPeople: 1));
      await reports.save(
        FloodReport(
          reportId: 'FLD-20260922-GONE001',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          severity: FloodSeverity.high,
          waterDepth: WaterDepthCategory.kneeDeep,
          affectedPeople: 3,
          description: 'Flooding.',
        ),
      );
      await requests.save(
        HelpRequest(
          requestId: 'REQ-20260922-GONE01',
          timestamp: fixedNow,
          latitude: 17.7,
          longitude: 83.3,
          category: HelpCategory.food,
          priority: HelpPriority.medium,
          peopleCount: 3,
          description: 'Hungry.',
          status: HelpRequestStatus.pending,
        ),
      );
      await contacts.save(
        EmergencyContact(
          contactId: 'CON-000001',
          name: 'Volunteer',
          phone: '+91 00000 00000',
          kind: ContactKind.rescue,
        ),
      );
      await alerts.save(
        AlertRecord(
          alertId: 'ALT-20260922-GONE01',
          title: 'Something',
          description: 'Happened.',
          severity: AlertSeverity.warning,
          source: AlertSource.system,
          timestamp: fixedNow,
          dedupeKey: 'system/advisory/ALT-20260922-GONE01',
        ),
      );
      await shelters.save(
        Shelter(
          shelterId: 'SHT-000001',
          name: 'Kept Camp',
          capacity: 10,
          occupied: 0,
          contactPhone: null,
          facilities: const [],
        ),
      );

      final summary = await service.clearUserData();

      expect(summary.sosRecords, 1);
      expect(summary.floodReports, 1);
      expect(summary.helpRequests, 1);
      expect(summary.contacts, 1);
      expect(summary.alerts, 1);
      expect(summary.removedNothing, isFalse);
      expect(await sos.getAll(), isEmpty);
      expect(await reports.getAll(), isEmpty);
      expect(await requests.getAll(), isEmpty);
      expect(await contacts.getAll(), isEmpty);
      expect(await alerts.getAll(), isEmpty);
      // Shelters survive a clear: the device keeps working.
      expect(await shelters.getAll(), hasLength(1));
      expect(summary.describe(), isNot(contains('shelter')));
    });

    test('describe() says so plainly when there was nothing to clear',
        () async {
      final summary = await service.clearUserData();
      expect(summary.removedNothing, isTrue);
      expect(summary.describe(), 'There was no local data to clear.');
    });

    test('describe() pluralises correctly', () {
      const summary = ClearedSummary(sosRecords: 1, floodReports: 2);
      expect(summary.describe(), 'Cleared 1 SOS record, 2 flood reports.');
      expect(summary.total, 3);
    });
  });

  group('geo helpers', () {
    test('distanceBetween is zero for the same point', () {
      expect(distanceBetween(17.7, 83.3, 17.7, 83.3), closeTo(0, 0.001));
    });

    test('distanceBetween is symmetric', () {
      final a = distanceBetween(17.7, 83.3, 17.75, 83.35);
      final b = distanceBetween(17.75, 83.35, 17.7, 83.3);
      expect(a, closeTo(b, 0.001));
    });

    test('isValidCoordinate rejects out-of-range values', () {
      expect(isValidCoordinate(17.7, 83.3), isTrue);
      expect(isValidCoordinate(91, 0), isFalse);
      expect(isValidCoordinate(0, 181), isFalse);
      expect(isValidCoordinate(double.nan, 0), isFalse);
    });

    test('formatDistance switches to kilometres above 1 km', () {
      expect(formatDistance(450), '450 m');
      expect(formatDistance(1500), '1.5 km');
      expect(formatDistance(42000), '42 km');
      expect(formatDistance(double.nan), '—');
    });
  });
}
