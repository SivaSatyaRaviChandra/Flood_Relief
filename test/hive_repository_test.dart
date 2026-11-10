/// Repository integration tests against real Hive file storage.
///
/// These run as plain `test()`s (real async) because Hive file I/O never
/// completes inside `testWidgets`' fake-async zone.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:flood_relief/core/constants/app_constants.dart';
import 'package:flood_relief/models/app_user.dart';
import 'package:flood_relief/models/enums/emergency_type.dart';
import 'package:flood_relief/models/enums/sos_priority.dart';
import 'package:flood_relief/models/enums/sos_status.dart';
import 'package:flood_relief/models/enums/team_status.dart';
import 'package:flood_relief/models/people_info.dart';
import 'package:flood_relief/models/rescue_team.dart';
import 'package:flood_relief/models/sos_packet.dart';
import 'package:flood_relief/models/sos_request.dart';
import 'package:flood_relief/repositories/packet_repository.dart';
import 'package:flood_relief/repositories/rescue_repository.dart';
import 'package:flood_relief/repositories/settings_repository.dart';
import 'package:flood_relief/repositories/sos_repository.dart';
import 'package:flood_relief/repositories/user_repository.dart';

final DateTime fixedNow = DateTime.utc(2026, 9, 22, 12, 0, 0);

SosRequest _sos(String sosId, DateTime at, {String userId = 'USER-1'}) {
  return SosRequest(
    sosId: sosId,
    userId: userId,
    timestamp: at,
    latitude: 17.7,
    longitude: 83.3,
    accuracy: 12.0,
    people: const PeopleInfo(totalPeople: 2, childrenCount: 1),
    emergencyType: EmergencyType.rescueRequired,
    description: 'Water rising.',
    priority: SosPriority.high,
    status: SosStatus.pending,
    originDeviceId: 'DEVICE-ORIG1234',
  );
}

SosPacketMessage _packet(String id) {
  return SosPacketMessage(
    packetId: id,
    sosId: 'SOS-20260922-ABC123',
    originDeviceId: 'DEVICE-ORIG1234',
    senderDeviceId: 'DEVICE-ORIG1234',
    hopCount: 0,
    ttl: 8,
    timestamp: fixedNow,
    latitude: 17.7,
    longitude: 83.3,
    accuracy: 12.0,
    totalPeople: 2,
    childrenCount: 1,
    elderlyCount: 0,
    pregnantWomenCount: 0,
    specialAssistanceCount: 0,
    emergencyType: EmergencyType.rescueRequired,
    description: 'Water rising.',
    priority: SosPriority.high,
  );
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('floodrelief_hive');
    Hive.init(dir.path);
  });

  tearDown(() async {
    await Hive.close();
    try {
      await dir.delete(recursive: true);
    } catch (_) {
      // The directory may still be locked shortly after close on Windows.
    }
  });

  group('HiveSosRepository', () {
    test('persists, orders newest-first and supports delete', () async {
      final box = await Hive.openBox(Boxes.sos);
      final repo = HiveSosRepository(box);

      await repo.save(_sos('SOS-O1', fixedNow.subtract(const Duration(hours: 1))));
      await repo.save(_sos('SOS-N1', fixedNow));

      final all = await repo.getAll();
      expect(all.map((s) => s.sosId).toList(), ['SOS-N1', 'SOS-O1']);
      expect(await repo.getById('SOS-N1'), isNotNull);

      await repo.delete('SOS-N1');
      expect(await repo.getById('SOS-N1'), isNull);
      expect(await repo.getAll(), hasLength(1));
    });

    test('watchAll emits the current snapshot on first listen', () async {
      final box = await Hive.openBox(Boxes.sos);
      final repo = HiveSosRepository(box);
      await repo.save(_sos('SOS-A', fixedNow));

      final snapshots = <List<SosRequest>>[];
      final sub = repo.watchAll().listen(snapshots.add);
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();

      expect(snapshots, hasLength(1));
      expect(snapshots.first.map((s) => s.sosId), contains('SOS-A'));
    });
  });

  group('HivePacketRepository', () {
    test('persists packets and resolves duplicates', () async {
      final packets = await Hive.openBox(Boxes.packets);
      final outbox = await Hive.openBox(Boxes.outbox);
      final dupBox = await Hive.openBox(Boxes.dupCache);
      final repo = HivePacketRepository(packets, outbox, dupBox);

      await repo.savePacket(_packet('PKT-AAAA1111'));
      await repo.savePacket(_packet('PKT-BBBB2222'));
      expect(await repo.getPackets(), hasLength(2));

      expect(await repo.isDuplicate('PKT-AAAA1111'), isFalse);
      await repo.recordSeen('PKT-AAAA1111', fixedNow);
      expect(await repo.isDuplicate('PKT-AAAA1111'), isTrue);
    });

    test('tracks pending packets through mark/resolve', () async {
      final packets = await Hive.openBox(Boxes.packets);
      final outbox = await Hive.openBox(Boxes.outbox);
      final dupBox = await Hive.openBox(Boxes.dupCache);
      final repo = HivePacketRepository(packets, outbox, dupBox);

      await repo.markPending('PKT-PEND1234');
      expect(await repo.pendingPacketIds(), ['PKT-PEND1234']);

      await repo.markPendingResolved('PKT-PEND1234');
      expect(await repo.pendingPacketIds(), isEmpty);
    });
  });

  group('HiveUserRepository', () {
    test('persists the current user and clears it', () async {
      final box = await Hive.openBox(Boxes.user);
      final repo = HiveUserRepository(box);

      expect(await repo.currentUser(), isNull);
      await repo.saveUser(AppUser(
        userId: 'USER-TEST01',
        displayName: 'Ana',
        role: UserRole.affected,
        createdAt: fixedNow,
      ));
      final user = await repo.currentUser();
      expect(user!.userId, 'USER-TEST01');
      expect(user.role, UserRole.affected);

      await repo.clear();
      expect(await repo.currentUser(), isNull);
    });

    test('watchUser emits current and subsequent users', () async {
      final box = await Hive.openBox(Boxes.user);
      final repo = HiveUserRepository(box);

      final events = <AppUser?>[];
      final sub = repo.watchUser().listen(events.add);
      await Future<void>.delayed(Duration.zero);

      await repo.saveUser(AppUser(
        userId: 'USER-TEST01',
        displayName: 'Ana',
        role: UserRole.affected,
      ));
      await Future<void>.delayed(Duration.zero);

      await sub.cancel();
      expect(events.length, greaterThanOrEqualTo(2));
      expect(events.last!.userId, 'USER-TEST01');
    });
  });

  group('HiveRescueRepository', () {
    test('persists teams sorted by name', () async {
      final box = await Hive.openBox(Boxes.teams);
      final repo = HiveRescueRepository(box);

      await repo.saveTeam(const RescueTeam(
        teamId: 'TEAM-Z',
        teamName: 'Zulu Unit',
        teamLeader: 'L',
        contact: '1',
        status: TeamStatus.available,
      ));
      await repo.saveTeam(const RescueTeam(
        teamId: 'TEAM-A',
        teamName: 'Alpha Unit',
        teamLeader: 'L',
        contact: '2',
        status: TeamStatus.responding,
      ));

      final teams = await repo.getTeams();
      expect(teams.map((t) => t.teamName).toList(), ['Alpha Unit', 'Zulu Unit']);
      expect((await repo.getById('TEAM-A'))!.status, TeamStatus.responding);
    });
  });

  group('HiveSettingsRepository', () {
    test('stores booleans and strings with fallbacks', () async {
      final box = await Hive.openBox(Boxes.settings);
      final repo = HiveSettingsRepository(box);

      expect(await repo.getBool('demoMode'), isFalse);
      expect(await repo.getBool('demoMode', fallback: true), isTrue);
      await repo.setBool('demoMode', true);
      expect(await repo.getBool('demoMode'), isTrue);

      expect(await repo.getString('role'), '');
      await repo.setString('role', 'RESCUE');
      expect(await repo.getString('role'), 'RESCUE');
    });
  });
}